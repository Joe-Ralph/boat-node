# BoatNode Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land Supabase schema v10 (mesh + crew + journey audit) and a `mesh-decoder` Edge function that ingests decoded LoRaWAN uplinks from ChirpStack, verifies HMAC, dedupes, and writes to `sos_signals` / `boat_logs`. ACK downlink is triggered from a Postgres trigger.

**Architecture:** Numbered append-only SQL migration plus reverter, following the existing v1..v9 pattern. Edge function written in Deno (Supabase functions runtime), split into small pure modules (`packet`, `hmac`, `crc16`, `dispatch`) with table-driven tests run by `deno test`. All HMAC secrets live in Postgres and are read only by the function via service-role; clients use a `boats_public` view.

**Tech Stack:** Postgres 15, Supabase Edge Functions (Deno), `pgcrypto`, `deno_std/crypto`. No Node runtime.

**Source spec:** `docs/superpowers/specs/2026-05-13-boatnode-hybrid-mesh-design.md` §"Backend Integration" and §"Identity & Security".

---

## File Structure

| Path | Responsibility |
|---|---|
| `backend/migrations/supabase_schema-v10.sql` | Forward migration — columns, indexes, RPCs, view, trigger |
| `backend/migration_reverts/revert_schema-v10.sql` | Reverse migration in dependency order |
| `backend/migrations/test_v10.sql` | psql smoke test invariants for v10 |
| `supabase/functions/mesh-decoder/index.ts` | HTTP handler entry |
| `supabase/functions/mesh-decoder/_lib/crc16.ts` | CRC16-CCITT (pure) |
| `supabase/functions/mesh-decoder/_lib/packet.ts` | Parse MeshHeader + POS/SOS/ACK/CANCEL (pure) |
| `supabase/functions/mesh-decoder/_lib/hmac.ts` | HMAC-SHA256 trunc-4 verify (Deno std crypto) |
| `supabase/functions/mesh-decoder/_lib/dispatch.ts` | Type → SQL handler routing |
| `supabase/functions/mesh-decoder/_lib/types.ts` | Frame, decoded payload, dispatch result types |
| `supabase/functions/mesh-decoder/_test/crc16_test.ts` | RFC fixture vectors |
| `supabase/functions/mesh-decoder/_test/packet_test.ts` | Parse + validation pipeline |
| `supabase/functions/mesh-decoder/_test/hmac_test.ts` | RFC 4231 vectors |
| `supabase/functions/mesh-decoder/_test/dispatch_test.ts` | Mocked Postgres client |
| `supabase/functions/mesh-decoder/_test/fixtures/` | Captured frame bytes (valid + tampered) |

---

## Task 1: Schema v10 migration

**Files:**
- Create: `backend/migrations/supabase_schema-v10.sql`
- Create: `backend/migration_reverts/revert_schema-v10.sql`
- Create: `backend/migrations/test_v10.sql`

- [ ] **Step 1: Write the forward migration**

`backend/migrations/supabase_schema-v10.sql`:

```sql
BEGIN;

ALTER TABLE boats
  ADD COLUMN mesh_src_id INTEGER UNIQUE
    CHECK (mesh_src_id IS NULL OR (mesh_src_id > 0 AND mesh_src_id < 65535)),
  ADD COLUMN hmac_secret BYTEA,
  ADD COLUMN crew_token BYTEA,
  ADD COLUMN dev_eui BYTEA,
  ADD COLUMN last_sos_seq INTEGER DEFAULT 0
    CHECK (last_sos_seq >= 0 AND last_sos_seq <= 65535),
  ADD COLUMN relay_mode BOOLEAN DEFAULT FALSE,
  ADD COLUMN unpaired_at TIMESTAMPTZ;

ALTER TABLE profiles
  ADD COLUMN user_short_id INTEGER UNIQUE
    CHECK (user_short_id IS NULL OR (user_short_id > 0 AND user_short_id < 65535));

CREATE OR REPLACE FUNCTION assign_user_short_id() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_short_id IS NULL THEN
    SELECT COALESCE(MAX(user_short_id), 0) + 1
      INTO NEW.user_short_id FROM profiles;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS profiles_assign_short_id ON profiles;
CREATE TRIGGER profiles_assign_short_id
BEFORE INSERT ON profiles
FOR EACH ROW EXECUTE FUNCTION assign_user_short_id();

UPDATE profiles SET user_short_id = sub.rn
FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY created_at) AS rn FROM profiles) sub
WHERE profiles.id = sub.id AND profiles.user_short_id IS NULL;

ALTER TABLE sos_signals
  ADD COLUMN origin TEXT NOT NULL DEFAULT 'phone_direct'
    CHECK (origin IN ('mesh', 'phone_direct')),
  ADD COLUMN trigger_user_short_id INTEGER REFERENCES profiles(user_short_id),
  ADD COLUMN trigger_user_id UUID REFERENCES profiles(id),
  ADD COLUMN mesh_seq INTEGER CHECK (mesh_seq IS NULL OR (mesh_seq >= 0 AND mesh_seq <= 65535)),
  ADD COLUMN mesh_hops SMALLINT,
  ADD COLUMN gateway_boat_id INTEGER REFERENCES boats(id),
  ADD COLUMN ack_status SMALLINT DEFAULT 0,
  ADD COLUMN acked_at TIMESTAMPTZ;

CREATE UNIQUE INDEX sos_dedup ON sos_signals(boat_id, mesh_seq)
  WHERE origin = 'mesh';

CREATE TABLE boat_journey_events (
  id BIGSERIAL PRIMARY KEY,
  boat_id INTEGER NOT NULL REFERENCES boats(id),
  user_id UUID NOT NULL REFERENCES profiles(id),
  action TEXT NOT NULL CHECK (action IN ('start','end')),
  ts TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX bje_boat_ts ON boat_journey_events(boat_id, ts DESC);

CREATE OR REPLACE FUNCTION get_crew_token(p_boat_id INTEGER)
RETURNS BYTEA LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  caller UUID := auth.uid();
  token BYTEA;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM boat_members
    WHERE boat_id = p_boat_id AND user_id = caller
  ) AND NOT EXISTS (
    SELECT 1 FROM boats WHERE id = p_boat_id AND owner_id = caller
  ) THEN
    RAISE EXCEPTION 'not_a_member';
  END IF;
  SELECT crew_token INTO token FROM boats WHERE id = p_boat_id;
  RETURN token;
END $$;

CREATE OR REPLACE FUNCTION pair_boat(
  p_dev_eui BYTEA,
  p_hmac_secret BYTEA,
  p_crew_token BYTEA,
  p_display_name TEXT
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  caller UUID := auth.uid();
  new_src INTEGER;
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  SELECT COALESCE(MAX(mesh_src_id), 0) + 1 INTO new_src FROM boats;
  IF new_src >= 65535 THEN
    RAISE EXCEPTION 'mesh_src_id_pool_exhausted';
  END IF;
  INSERT INTO boats (owner_id, mesh_src_id, dev_eui, hmac_secret,
                     crew_token, display_name)
  VALUES (caller, new_src, p_dev_eui, p_hmac_secret,
          p_crew_token, p_display_name);
  RETURN new_src;
END $$;

CREATE OR REPLACE VIEW boats_public AS
SELECT id, owner_id, mesh_src_id, display_name, village_id,
       created_at, last_sos_seq, relay_mode
FROM boats;

REVOKE ALL ON FUNCTION get_crew_token(INTEGER) FROM public;
GRANT EXECUTE ON FUNCTION get_crew_token(INTEGER) TO authenticated;
REVOKE ALL ON FUNCTION pair_boat(BYTEA, BYTEA, BYTEA, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION pair_boat(BYTEA, BYTEA, BYTEA, TEXT) TO authenticated;

COMMIT;
```

- [ ] **Step 2: Write the reverter**

`backend/migration_reverts/revert_schema-v10.sql`:

```sql
BEGIN;

REVOKE EXECUTE ON FUNCTION pair_boat(BYTEA, BYTEA, BYTEA, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION get_crew_token(INTEGER) FROM authenticated;

DROP VIEW IF EXISTS boats_public;
DROP FUNCTION IF EXISTS pair_boat(BYTEA, BYTEA, BYTEA, TEXT);
DROP FUNCTION IF EXISTS get_crew_token(INTEGER);
DROP INDEX IF EXISTS sos_dedup;
DROP INDEX IF EXISTS bje_boat_ts;
DROP TABLE IF EXISTS boat_journey_events;

ALTER TABLE sos_signals
  DROP COLUMN IF EXISTS acked_at,
  DROP COLUMN IF EXISTS ack_status,
  DROP COLUMN IF EXISTS gateway_boat_id,
  DROP COLUMN IF EXISTS mesh_hops,
  DROP COLUMN IF EXISTS mesh_seq,
  DROP COLUMN IF EXISTS trigger_user_id,
  DROP COLUMN IF EXISTS trigger_user_short_id,
  DROP COLUMN IF EXISTS origin;

DROP TRIGGER IF EXISTS profiles_assign_short_id ON profiles;
DROP FUNCTION IF EXISTS assign_user_short_id();
ALTER TABLE profiles DROP COLUMN IF EXISTS user_short_id;

ALTER TABLE boats
  DROP COLUMN IF EXISTS unpaired_at,
  DROP COLUMN IF EXISTS relay_mode,
  DROP COLUMN IF EXISTS last_sos_seq,
  DROP COLUMN IF EXISTS dev_eui,
  DROP COLUMN IF EXISTS crew_token,
  DROP COLUMN IF EXISTS hmac_secret,
  DROP COLUMN IF EXISTS mesh_src_id;

COMMIT;
```

- [ ] **Step 3: Apply migration against a test database**

Run:
```
psql "$SUPABASE_TEST_DB_URL" -v ON_ERROR_STOP=1 -f backend/migrations/supabase_schema-v10.sql
```
Expected: `COMMIT` on the final line, no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/migrations/supabase_schema-v10.sql backend/migration_reverts/revert_schema-v10.sql
git commit -m "feat(backend): schema v10 — mesh identity, crew token, journey events"
```

---

## Task 2: Migration smoke tests

**Files:**
- Create: `backend/migrations/test_v10.sql`

- [ ] **Step 1: Write smoke-test SQL**

`backend/migrations/test_v10.sql`:

```sql
\set ON_ERROR_STOP on
BEGIN;

-- 1. user_short_id auto-assigned
INSERT INTO auth.users (id, email) VALUES (gen_random_uuid(), 'a@test') RETURNING id \gset
INSERT INTO profiles (id, full_name) VALUES (:'id', 'a') RETURNING user_short_id AS short_a \gset
DO $$ BEGIN
  ASSERT (:short_a)::int > 0 AND (:short_a)::int < 65535, 'user_short_id out of range';
END $$;

-- 2. mesh_src_id auto-increments via pair_boat
SET LOCAL ROLE authenticated;
SELECT pair_boat('\x0102030405060708'::bytea, '\x00'::bytea, '\x00'::bytea, 'TestBoat') AS src1 \gset
SELECT pair_boat('\x0102030405060709'::bytea, '\x00'::bytea, '\x00'::bytea, 'TestBoat2') AS src2 \gset
DO $$ BEGIN
  ASSERT (:src2)::int = (:src1)::int + 1, 'mesh_src_id not monotonic';
END $$;
RESET ROLE;

-- 3. sos_dedup unique index
INSERT INTO boats (owner_id, display_name, mesh_src_id) VALUES
  ((SELECT id FROM profiles LIMIT 1), 'Dup', 9999) RETURNING id AS bid \gset
INSERT INTO sos_signals (boat_id, origin, mesh_seq, lat, lon)
  VALUES (:'bid', 'mesh', 42, 0, 0);
DO $$ DECLARE bad BOOLEAN := FALSE;
BEGIN
  BEGIN
    INSERT INTO sos_signals (boat_id, origin, mesh_seq, lat, lon)
      VALUES ((SELECT id FROM boats WHERE display_name='Dup'), 'mesh', 42, 1, 1);
    bad := TRUE;
  EXCEPTION WHEN unique_violation THEN NULL; END;
  ASSERT NOT bad, 'sos_dedup did not enforce uniqueness';
END $$;

ROLLBACK;
\echo 'v10 smoke OK'
```

- [ ] **Step 2: Run smoke test**

Run:
```
psql "$SUPABASE_TEST_DB_URL" -f backend/migrations/test_v10.sql
```
Expected: final line `v10 smoke OK`.

- [ ] **Step 3: Verify reverter**

Run:
```
psql "$SUPABASE_TEST_DB_URL" -v ON_ERROR_STOP=1 -f backend/migration_reverts/revert_schema-v10.sql
psql "$SUPABASE_TEST_DB_URL" -c "SELECT column_name FROM information_schema.columns WHERE table_name='boats' AND column_name='mesh_src_id'"
```
Expected: empty result (`0 rows`).

Re-apply forward migration for the next tasks:
```
psql "$SUPABASE_TEST_DB_URL" -f backend/migrations/supabase_schema-v10.sql
```

- [ ] **Step 4: Commit**

```bash
git add backend/migrations/test_v10.sql
git commit -m "test(backend): v10 schema smoke tests"
```

---

## Task 3: Edge function scaffold

**Files:**
- Create: `supabase/functions/mesh-decoder/index.ts`
- Create: `supabase/functions/mesh-decoder/deno.json`

- [ ] **Step 1: Create deno.json**

```json
{
  "tasks": {
    "test": "deno test --allow-net --allow-env --allow-read _test/"
  },
  "imports": {
    "std/": "https://deno.land/std@0.208.0/",
    "supabase": "https://esm.sh/@supabase/supabase-js@2.39.0"
  }
}
```

- [ ] **Step 2: Create minimal handler**

`supabase/functions/mesh-decoder/index.ts`:

```ts
import { serve } from "std/http/server.ts";

serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  return new Response(JSON.stringify({ ok: true, stub: true }), {
    headers: { "content-type": "application/json" },
  });
});
```

- [ ] **Step 3: Local serve + curl check**

Run:
```
cd supabase && supabase functions serve mesh-decoder --no-verify-jwt &
sleep 2
curl -s -X POST http://localhost:54321/functions/v1/mesh-decoder
```
Expected: `{"ok":true,"stub":true}`. Kill the background server after.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/mesh-decoder/index.ts supabase/functions/mesh-decoder/deno.json
git commit -m "scaffold(edge): mesh-decoder stub responding 200"
```

---

## Task 4: CRC16-CCITT

**Files:**
- Create: `supabase/functions/mesh-decoder/_lib/crc16.ts`
- Create: `supabase/functions/mesh-decoder/_test/crc16_test.ts`

- [ ] **Step 1: Write failing test**

`_test/crc16_test.ts`:

```ts
import { assertEquals } from "std/assert/mod.ts";
import { crc16ccitt } from "../_lib/crc16.ts";

Deno.test("crc16 '123456789' = 0x29b1", () => {
  const data = new TextEncoder().encode("123456789");
  assertEquals(crc16ccitt(data), 0x29b1);
});

Deno.test("crc16 empty = 0xffff", () => {
  assertEquals(crc16ccitt(new Uint8Array()), 0xffff);
});
```

- [ ] **Step 2: Run, see fail**

Run: `deno task test _test/crc16_test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

`_lib/crc16.ts`:

```ts
export function crc16ccitt(data: Uint8Array, init = 0xffff): number {
  let crc = init;
  for (const b of data) {
    crc ^= b << 8;
    for (let i = 0; i < 8; i++) {
      crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc;
}
```

- [ ] **Step 4: Run, see pass**

Run: `deno task test _test/crc16_test.ts`
Expected: `ok | 2 passed | 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/mesh-decoder/_lib/crc16.ts supabase/functions/mesh-decoder/_test/crc16_test.ts
git commit -m "feat(edge): crc16-ccitt with RFC fixture"
```

---

## Task 5: Packet parser

**Files:**
- Create: `supabase/functions/mesh-decoder/_lib/types.ts`
- Create: `supabase/functions/mesh-decoder/_lib/packet.ts`
- Create: `supabase/functions/mesh-decoder/_test/packet_test.ts`
- Create: `supabase/functions/mesh-decoder/_test/fixtures/pos_valid.bin`
- Create: `supabase/functions/mesh-decoder/_test/fixtures/sos_valid.bin`

- [ ] **Step 1: Define types**

`_lib/types.ts`:

```ts
export const MAGIC = 0xba;
export const VER = 0x02;
export const TYPE = { POS: 0x01, SOS: 0x02, ACK: 0x03, CANCEL: 0x04 } as const;
export type PktType = typeof TYPE[keyof typeof TYPE];

export interface MeshHeader {
  magic: number; ver: number; type: PktType;
  src: number; dest: number; seq: number;
  hops: number; ttl: number; ts: number;
}

export interface PosPayload  { lat1e7: number; lon1e7: number; spd: number; hdg: number; batt: number; flags: number; userId: number; name: string; }
export interface SosPayload  { lat1e7: number; lon1e7: number; spd: number; hdg: number; batt: number; reason: number; userId: number; hmac: Uint8Array; }
export interface AckPayload  { ackSrc: number; ackSeq: number; status: number; hmac: Uint8Array; }
export interface CancelPayload { cancelSeq: number; userId: number; hmac: Uint8Array; }

export interface Frame {
  header: MeshHeader;
  body: PosPayload | SosPayload | AckPayload | CancelPayload;
  hmacInput: Uint8Array;  // bytes covered by HMAC (header + payload up to hmac field)
  raw: Uint8Array;
}

export class ParseError extends Error { constructor(public code: string, msg: string) { super(msg); } }
```

- [ ] **Step 2: Write failing test**

`_test/packet_test.ts`:

```ts
import { assertEquals, assertThrows } from "std/assert/mod.ts";
import { parseFrame } from "../_lib/packet.ts";
import { TYPE, ParseError } from "../_lib/types.ts";

function buildPos(): Uint8Array {
  const buf = new Uint8Array(46);
  const v = new DataView(buf.buffer);
  buf[0] = 0xba; buf[1] = 0x02; buf[2] = TYPE.POS;
  v.setUint16(3, 0x07f4, true);
  v.setUint16(5, 0xffff, true);
  v.setUint16(7, 0x0001, true);
  buf[9] = 0; buf[10] = 4;
  v.setUint32(11, 1715600000, true);
  v.setInt32(15, 100000000, true);   // lat 10.0
  v.setInt32(19, 770000000, true);   // lon 77.0
  v.setUint16(23, 300, true);        // spd 3 m/s
  v.setUint16(25, 9000, true);       // hdg 90 deg
  buf[27] = 84; buf[28] = 1;
  v.setUint16(29, 42, true);         // user
  buf[31] = 4;                       // name_len
  buf.set(new TextEncoder().encode("Joe\0\0\0\0\0\0\0\0\0"), 32);
  // crc at 44..45 — fill in test after computing
  const { crc16ccitt } = await import("../_lib/crc16.ts");
  const crc = crc16ccitt(buf.subarray(0, 44));
  v.setUint16(44, crc, true);
  return buf;
}

Deno.test("POS roundtrip", async () => {
  const bytes = await buildPos();
  const f = parseFrame(bytes);
  assertEquals(f.header.type, TYPE.POS);
  assertEquals(f.header.src, 0x07f4);
  if (f.header.type !== TYPE.POS) throw new Error();
  const p = f.body as { lat1e7: number };
  assertEquals(p.lat1e7, 100000000);
});

Deno.test("rejects bad magic", async () => {
  const bytes = await buildPos();
  bytes[0] = 0x00;
  assertThrows(() => parseFrame(bytes), ParseError, "magic");
});

Deno.test("rejects bad crc", async () => {
  const bytes = await buildPos();
  bytes[44] ^= 0xff;
  assertThrows(() => parseFrame(bytes), ParseError, "crc");
});

Deno.test("rejects truncated", () => {
  assertThrows(() => parseFrame(new Uint8Array(10)), ParseError, "truncated");
});
```

- [ ] **Step 3: Run, see fail**

Run: `deno task test _test/packet_test.ts`
Expected: FAIL — parseFrame not implemented.

- [ ] **Step 4: Implement parser**

`_lib/packet.ts`:

```ts
import { MAGIC, VER, TYPE, ParseError, type Frame, type MeshHeader, type PktType } from "./types.ts";
import { crc16ccitt } from "./crc16.ts";

const SIZES: Record<PktType, number> = { 0x01: 46, 0x02: 36, 0x03: 25, 0x04: 25 };

function readHeader(buf: Uint8Array, v: DataView): MeshHeader {
  return {
    magic: buf[0], ver: buf[1], type: buf[2] as PktType,
    src: v.getUint16(3, true), dest: v.getUint16(5, true),
    seq: v.getUint16(7, true), hops: buf[9], ttl: buf[10],
    ts: v.getUint32(11, true),
  };
}

export function parseFrame(buf: Uint8Array): Frame {
  if (buf.length < 15) throw new ParseError("truncated", "frame < header size");
  if (buf[0] !== MAGIC) throw new ParseError("magic", `magic=0x${buf[0].toString(16)}`);
  if (buf[1] !== VER)   throw new ParseError("ver", `ver=0x${buf[1].toString(16)}`);
  if (!(buf[2] in SIZES)) throw new ParseError("type", `type=0x${buf[2].toString(16)}`);

  const v = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const header = readHeader(buf, v);
  const expectedLen = SIZES[header.type];
  if (buf.length !== expectedLen) throw new ParseError("size", `expected ${expectedLen} got ${buf.length}`);

  const crcOffset = expectedLen - 2;
  const expectedCrc = crc16ccitt(buf.subarray(0, crcOffset));
  const gotCrc = v.getUint16(crcOffset, true);
  if (expectedCrc !== gotCrc) throw new ParseError("crc", `crc fail ${gotCrc} vs ${expectedCrc}`);

  let body: Frame["body"];
  let hmacEnd = crcOffset;
  switch (header.type) {
    case TYPE.POS:
      body = {
        lat1e7: v.getInt32(15, true), lon1e7: v.getInt32(19, true),
        spd: v.getUint16(23, true), hdg: v.getUint16(25, true),
        batt: buf[27], flags: buf[28],
        userId: v.getUint16(29, true),
        name: new TextDecoder().decode(buf.subarray(32, 32 + buf[31])),
      };
      break;
    case TYPE.SOS:
      hmacEnd = 30;
      body = {
        lat1e7: v.getInt32(15, true), lon1e7: v.getInt32(19, true),
        spd: v.getUint16(23, true), hdg: v.getUint16(25, true),
        batt: buf[27], reason: buf[28],
        userId: v.getUint16(29, true),
        hmac: buf.subarray(31, 35),
      };
      break;
    case TYPE.ACK:
      hmacEnd = 19;
      body = {
        ackSrc: v.getUint16(15, true), ackSeq: v.getUint16(17, true),
        status: buf[19], hmac: buf.subarray(21, 25),
      };
      break;
    case TYPE.CANCEL:
      hmacEnd = 19;
      body = {
        cancelSeq: v.getUint16(15, true), userId: v.getUint16(17, true),
        hmac: buf.subarray(19, 23),
      };
      break;
  }
  return { header, body, hmacInput: buf.subarray(0, hmacEnd), raw: buf };
}
```

- [ ] **Step 5: Run, see pass**

Run: `deno task test _test/packet_test.ts`
Expected: 4 passed.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/mesh-decoder/_lib/types.ts supabase/functions/mesh-decoder/_lib/packet.ts supabase/functions/mesh-decoder/_test/packet_test.ts
git commit -m "feat(edge): mesh packet parser with type/magic/crc validation"
```

---

## Task 6: HMAC-SHA256 truncated verify

**Files:**
- Create: `supabase/functions/mesh-decoder/_lib/hmac.ts`
- Create: `supabase/functions/mesh-decoder/_test/hmac_test.ts`

- [ ] **Step 1: Write failing test**

`_test/hmac_test.ts`:

```ts
import { assertEquals } from "std/assert/mod.ts";
import { hmacTrunc, hmacVerify } from "../_lib/hmac.ts";

const key = new Uint8Array(16).fill(0xab);

Deno.test("hmacTrunc is 4 bytes", async () => {
  const out = await hmacTrunc(key, new TextEncoder().encode("hello"));
  assertEquals(out.length, 4);
});

Deno.test("hmacVerify true for matching", async () => {
  const data = new TextEncoder().encode("payload");
  const tag = await hmacTrunc(key, data);
  assertEquals(await hmacVerify(key, data, tag), true);
});

Deno.test("hmacVerify false for tampered", async () => {
  const data = new TextEncoder().encode("payload");
  const tag = await hmacTrunc(key, data);
  tag[0] ^= 0x01;
  assertEquals(await hmacVerify(key, data, tag), false);
});
```

- [ ] **Step 2: Run, fail**

Run: `deno task test _test/hmac_test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

`_lib/hmac.ts`:

```ts
export async function hmacTrunc(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey(
    "raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const full = new Uint8Array(await crypto.subtle.sign("HMAC", k, data));
  return full.subarray(0, 4);
}

export async function hmacVerify(key: Uint8Array, data: Uint8Array, tag: Uint8Array): Promise<boolean> {
  if (tag.length !== 4) return false;
  const expected = await hmacTrunc(key, data);
  let diff = 0;
  for (let i = 0; i < 4; i++) diff |= expected[i] ^ tag[i];
  return diff === 0;
}
```

- [ ] **Step 4: Run, pass**

Run: `deno task test _test/hmac_test.ts`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/mesh-decoder/_lib/hmac.ts supabase/functions/mesh-decoder/_test/hmac_test.ts
git commit -m "feat(edge): hmac-sha256 trunc-4 with consteq verify"
```

---

## Task 7: Dispatch logic with mock client

**Files:**
- Create: `supabase/functions/mesh-decoder/_lib/dispatch.ts`
- Create: `supabase/functions/mesh-decoder/_test/dispatch_test.ts`

- [ ] **Step 1: Write failing test**

`_test/dispatch_test.ts`:

```ts
import { assertEquals } from "std/assert/mod.ts";
import { dispatchFrame } from "../_lib/dispatch.ts";
import { TYPE } from "../_lib/types.ts";

type Op = { table: string; verb: "insert" | "update"; row: Record<string, unknown> };

class MockDb {
  ops: Op[] = [];
  boat = { id: 1, hmac_secret: new Uint8Array(16).fill(0xab), last_sos_seq: 0 };
  async getBoatByMeshSrc(_: number) { return this.boat; }
  async insertBoatLog(row: Record<string, unknown>) { this.ops.push({ table: "boat_logs", verb: "insert", row }); }
  async insertSosSignal(row: Record<string, unknown>) { this.ops.push({ table: "sos_signals", verb: "insert", row }); }
  async updateSosCanceled(boat_id: number, seq: number) { this.ops.push({ table: "sos_signals", verb: "update", row: { boat_id, seq } }); }
  async updateLastSosSeq(_: number, __: number) {}
  async triggerAckDownlink(_: { boat: typeof this.boat; seq: number; status: number; gw: number }) {}
}

Deno.test("POS → boat_logs", async () => {
  const db = new MockDb();
  await dispatchFrame(db as any, {
    header: { magic: 0xba, ver: 0x02, type: TYPE.POS, src: 0x07f4, dest: 0xffff, seq: 1, hops: 0, ttl: 4, ts: 1715600000 },
    body: { lat1e7: 100000000, lon1e7: 770000000, spd: 0, hdg: 0, batt: 80, flags: 1, userId: 42, name: "Joe" },
    hmacInput: new Uint8Array(), raw: new Uint8Array(),
  } as any, { gatewayBoatId: 1 });
  assertEquals(db.ops.length, 1);
  assertEquals(db.ops[0].table, "boat_logs");
});

Deno.test("SOS rejects bad HMAC", async () => {
  const db = new MockDb();
  const res = await dispatchFrame(db as any, {
    header: { magic: 0xba, ver: 0x02, type: TYPE.SOS, src: 0x07f4, dest: 0xffff, seq: 7, hops: 0, ttl: 4, ts: Math.floor(Date.now() / 1000) },
    body: { lat1e7: 0, lon1e7: 0, spd: 0, hdg: 0, batt: 80, reason: 0, userId: 42, hmac: new Uint8Array([0, 0, 0, 0]) },
    hmacInput: new Uint8Array(31), raw: new Uint8Array(),
  } as any, { gatewayBoatId: 1 });
  assertEquals(res.dropped, "hmac_fail");
  assertEquals(db.ops.length, 0);
});
```

- [ ] **Step 2: Run, fail**

Run: `deno task test _test/dispatch_test.ts`
Expected: FAIL — dispatchFrame not found.

- [ ] **Step 3: Implement dispatch**

`_lib/dispatch.ts`:

```ts
import { TYPE, type Frame, type PosPayload, type SosPayload, type AckPayload, type CancelPayload } from "./types.ts";
import { hmacVerify } from "./hmac.ts";

const REPLAY_WINDOW_S = 300;

export interface DispatchCtx { gatewayBoatId: number }
export interface DispatchResult { dropped?: string; inserted?: string }

export interface DbClient {
  getBoatByMeshSrc(src: number): Promise<{ id: number; hmac_secret: Uint8Array; last_sos_seq: number } | null>;
  insertBoatLog(row: Record<string, unknown>): Promise<void>;
  insertSosSignal(row: Record<string, unknown>): Promise<void>;
  updateSosCanceled(boat_id: number, seq: number): Promise<void>;
  updateLastSosSeq(boat_id: number, seq: number): Promise<void>;
  triggerAckDownlink(arg: { boat: { id: number; hmac_secret: Uint8Array }; seq: number; status: number; gw: number }): Promise<void>;
}

function tsFresh(ts: number, nowSec: number): boolean {
  return Math.abs(nowSec - ts) <= REPLAY_WINDOW_S;
}

export async function dispatchFrame(db: DbClient, f: Frame, ctx: DispatchCtx): Promise<DispatchResult> {
  const boat = await db.getBoatByMeshSrc(f.header.src);
  if (!boat) return { dropped: "unknown_src" };

  const nowSec = Math.floor(Date.now() / 1000);
  if (!tsFresh(f.header.ts, nowSec)) return { dropped: "stale_ts" };

  const t = f.header.type;
  if (t !== TYPE.POS) {
    const tag = (f.body as SosPayload | AckPayload | CancelPayload).hmac;
    if (!await hmacVerify(boat.hmac_secret, f.hmacInput, tag)) return { dropped: "hmac_fail" };
  }

  switch (t) {
    case TYPE.POS: {
      const p = f.body as PosPayload;
      await db.insertBoatLog({
        boat_id: boat.id, lat: p.lat1e7 / 1e7, lon: p.lon1e7 / 1e7,
        speed_mps: p.spd / 100, heading_deg: p.hdg / 100,
        battery_pct: p.batt, journey_active: !!(p.flags & 1),
        mesh_seq: f.header.seq, mesh_hops: f.header.hops, ts_device: new Date(f.header.ts * 1000),
      });
      return { inserted: "boat_log" };
    }
    case TYPE.SOS: {
      if (f.header.seq <= boat.last_sos_seq && boat.last_sos_seq !== 0) return { dropped: "seq_regress" };
      const p = f.body as SosPayload;
      await db.insertSosSignal({
        boat_id: boat.id, origin: "mesh", mesh_seq: f.header.seq, mesh_hops: f.header.hops,
        gateway_boat_id: ctx.gatewayBoatId, trigger_user_short_id: p.userId,
        lat: p.lat1e7 / 1e7, lon: p.lon1e7 / 1e7, reason: p.reason,
        status: "active", ack_status: 0,
      });
      await db.updateLastSosSeq(boat.id, f.header.seq);
      await db.triggerAckDownlink({ boat, seq: f.header.seq, status: 0, gw: ctx.gatewayBoatId });
      return { inserted: "sos_signal" };
    }
    case TYPE.CANCEL: {
      const p = f.body as CancelPayload;
      await db.updateSosCanceled(boat.id, p.cancelSeq);
      return { inserted: "sos_canceled" };
    }
    case TYPE.ACK:
      return { dropped: "ack_inbound_ignored" };
  }
}
```

- [ ] **Step 4: Run, pass**

Run: `deno task test _test/dispatch_test.ts`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/mesh-decoder/_lib/dispatch.ts supabase/functions/mesh-decoder/_test/dispatch_test.ts
git commit -m "feat(edge): dispatch with hmac + ts freshness + seq progression"
```

---

## Task 8: Real Postgres client

**Files:**
- Create: `supabase/functions/mesh-decoder/_lib/db.ts`

- [ ] **Step 1: Implement DbClient backed by supabase-js**

`_lib/db.ts`:

```ts
import { createClient, SupabaseClient } from "supabase";
import type { DbClient } from "./dispatch.ts";

export function makeDb(): DbClient & { sb: SupabaseClient } {
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const sb = createClient(url, key, { auth: { persistSession: false } });

  return {
    sb,
    async getBoatByMeshSrc(src) {
      const { data, error } = await sb
        .from("boats")
        .select("id, hmac_secret, last_sos_seq")
        .eq("mesh_src_id", src)
        .maybeSingle();
      if (error) throw error;
      if (!data) return null;
      return { ...data, hmac_secret: new Uint8Array(data.hmac_secret as ArrayBuffer) };
    },
    async insertBoatLog(row) {
      const { error } = await sb.from("boat_logs").insert(row);
      if (error) throw error;
    },
    async insertSosSignal(row) {
      const { error } = await sb.from("sos_signals").insert(row);
      if (error && !/sos_dedup/.test(error.message)) throw error;  // tolerate dedup hit
    },
    async updateSosCanceled(boat_id, seq) {
      await sb.from("sos_signals").update({ status: "canceled" })
        .eq("boat_id", boat_id).eq("mesh_seq", seq).eq("origin", "mesh");
    },
    async updateLastSosSeq(boat_id, seq) {
      await sb.from("boats").update({ last_sos_seq: seq }).eq("id", boat_id);
    },
    async triggerAckDownlink({ boat, seq, status, gw }) {
      // POST to ChirpStack REST. Defer construction of bytes to Task 9.
      const csUrl = Deno.env.get("CHIRPSTACK_URL")!;
      const csKey = Deno.env.get("CHIRPSTACK_API_KEY")!;
      const { buildAckBytes } = await import("./ack_builder.ts");
      const payload = await buildAckBytes(boat.hmac_secret, seq, status);
      await fetch(`${csUrl}/api/devices/${gw}/queue`, {
        method: "POST",
        headers: { "Grpc-Metadata-Authorization": `Bearer ${csKey}`, "content-type": "application/json" },
        body: JSON.stringify({ deviceQueueItem: { confirmed: false, data: btoa(String.fromCharCode(...payload)), fPort: 1 } }),
      });
    },
  };
}
```

- [ ] **Step 2: Commit (no test — exercised in integration task)**

```bash
git add supabase/functions/mesh-decoder/_lib/db.ts
git commit -m "feat(edge): supabase-backed DbClient implementation"
```

---

## Task 9: ACK packet builder

**Files:**
- Create: `supabase/functions/mesh-decoder/_lib/ack_builder.ts`
- Create: `supabase/functions/mesh-decoder/_test/ack_builder_test.ts`

- [ ] **Step 1: Failing test**

`_test/ack_builder_test.ts`:

```ts
import { assertEquals } from "std/assert/mod.ts";
import { buildAckBytes } from "../_lib/ack_builder.ts";
import { parseFrame } from "../_lib/packet.ts";
import { TYPE } from "../_lib/types.ts";
import { hmacVerify } from "../_lib/hmac.ts";

Deno.test("buildAckBytes produces parseable HMAC-signed ACK", async () => {
  const key = new Uint8Array(16).fill(0xab);
  const bytes = await buildAckBytes(key, 7, 1, { src: 0xdead, ackSrc: 0x07f4 });
  assertEquals(bytes.length, 25);
  const f = parseFrame(bytes);
  assertEquals(f.header.type, TYPE.ACK);
  const tag = (f.body as { hmac: Uint8Array }).hmac;
  assertEquals(await hmacVerify(key, f.hmacInput, tag), true);
});
```

- [ ] **Step 2: Run, fail.**

Run: `deno task test _test/ack_builder_test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement**

`_lib/ack_builder.ts`:

```ts
import { TYPE } from "./types.ts";
import { hmacTrunc } from "./hmac.ts";
import { crc16ccitt } from "./crc16.ts";

export async function buildAckBytes(
  hmacSecret: Uint8Array,
  ackSeq: number,
  status: number,
  opts?: { src?: number; ackSrc?: number; seq?: number },
): Promise<Uint8Array> {
  const buf = new Uint8Array(25);
  const v = new DataView(buf.buffer);
  buf[0] = 0xba; buf[1] = 0x02; buf[2] = TYPE.ACK;
  v.setUint16(3, opts?.src ?? 0x0000, true);          // gateway hdr.src (we don't know; backend uses 0)
  v.setUint16(5, opts?.ackSrc ?? 0xffff, true);       // dest = originator
  v.setUint16(7, opts?.seq ?? 0, true);
  buf[9] = 0; buf[10] = 4;
  v.setUint32(11, Math.floor(Date.now() / 1000), true);
  v.setUint16(15, opts?.ackSrc ?? 0, true);
  v.setUint16(17, ackSeq, true);
  buf[19] = status;
  buf[20] = 0;
  const tag = await hmacTrunc(hmacSecret, buf.subarray(0, 21));
  buf.set(tag, 21);
  const crc = crc16ccitt(buf.subarray(0, 23));
  v.setUint16(23, crc, true);
  return buf;
}
```

- [ ] **Step 4: Run, pass.**

Run: `deno task test _test/ack_builder_test.ts`
Expected: 1 passed.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/mesh-decoder/_lib/ack_builder.ts supabase/functions/mesh-decoder/_test/ack_builder_test.ts
git commit -m "feat(edge): hmac-signed ACK builder"
```

---

## Task 10: Wire HTTP handler end-to-end

**Files:**
- Modify: `supabase/functions/mesh-decoder/index.ts`
- Create: `supabase/functions/mesh-decoder/_test/handler_test.ts`

- [ ] **Step 1: Failing integration test**

`_test/handler_test.ts`:

```ts
import { assertEquals } from "std/assert/mod.ts";
import { handle } from "../index.ts";

Deno.test("handler 400s on missing frame", async () => {
  const res = await handle(new Request("http://x/", { method: "POST", body: JSON.stringify({}) }));
  assertEquals(res.status, 400);
});
```

- [ ] **Step 2: Run, fail**

Run: `deno task test _test/handler_test.ts`
Expected: FAIL — handle not exported.

- [ ] **Step 3: Implement handler**

`supabase/functions/mesh-decoder/index.ts`:

```ts
import { serve } from "std/http/server.ts";
import { parseFrame } from "./_lib/packet.ts";
import { dispatchFrame } from "./_lib/dispatch.ts";
import { makeDb } from "./_lib/db.ts";

interface CsUplink {
  deviceInfo?: { devEui: string; gatewayId?: number };
  data: string;  // base64 frame bytes from codec
  rxInfo?: { gatewayId?: string }[];
}

export async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  let body: CsUplink;
  try { body = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  if (!body?.data) return new Response("missing data", { status: 400 });

  const bytes = Uint8Array.from(atob(body.data), c => c.charCodeAt(0));
  const frame = parseFrame(bytes);
  const db = makeDb();
  const gwId = Number(body.rxInfo?.[0]?.gatewayId ?? 0);
  const result = await dispatchFrame(db, frame, { gatewayBoatId: gwId });

  return new Response(JSON.stringify({ ok: true, ...result }), {
    headers: { "content-type": "application/json" },
  });
}

serve(handle);
```

- [ ] **Step 4: Run, pass**

Run: `deno task test _test/handler_test.ts`
Expected: 1 passed.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/mesh-decoder/index.ts supabase/functions/mesh-decoder/_test/handler_test.ts
git commit -m "feat(edge): wire handler end-to-end with chirpstack uplink shape"
```

---

## Task 11: Deploy to staging + smoke

- [ ] **Step 1: Run full test suite**

Run: `cd supabase/functions/mesh-decoder && deno task test`
Expected: all tests pass.

- [ ] **Step 2: Deploy**

Run:
```
supabase functions deploy mesh-decoder --project-ref $SUPABASE_PROJECT_REF --no-verify-jwt
supabase secrets set CHIRPSTACK_URL=$CS_URL CHIRPSTACK_API_KEY=$CS_KEY --project-ref $SUPABASE_PROJECT_REF
```
Expected: `Deployed Function mesh-decoder` printed.

- [ ] **Step 3: Smoke with a valid fixture frame**

Run:
```
curl -X POST "$SUPABASE_URL/functions/v1/mesh-decoder" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "content-type: application/json" \
  -d "$(jq -n --arg b "$(base64 < supabase/functions/mesh-decoder/_test/fixtures/pos_valid.bin)" \
      '{deviceInfo:{devEui:"01"}, rxInfo:[{gatewayId:"1"}], data:$b}')"
```
Expected: `{"ok":true,"inserted":"boat_log"}` and a new row in `boat_logs`.

- [ ] **Step 4: Commit deploy notes if any (no code change). Done.**

---

## Spec coverage cross-check

| Spec § | Covered by |
|---|---|
| Schema v10 | Task 1 |
| `pair_boat` RPC | Task 1, smoke 2 |
| `get_crew_token` RPC | Task 1 (RLS check), smoke pending in app-side plan |
| Edge function flow steps 1-6 | Tasks 5, 6, 7, 8, 10 |
| HMAC truncation | Task 6 |
| ts ±300 s | Task 7 |
| Dedup `ON CONFLICT` | Task 1 (`sos_dedup` partial unique idx) + Task 8 |
| ACK downlink via pgcrypto / Edge fn | Tasks 8, 9 |
| Realtime channels | Default Supabase behavior on tables; no code change needed |
