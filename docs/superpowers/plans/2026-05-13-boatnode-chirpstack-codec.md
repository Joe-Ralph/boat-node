# ChirpStack Codec Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide ChirpStack Application Server with a JavaScript codec that parses the raw LoRaWAN payload of a mesh frame into structured fields, and serializes outgoing ACK downlinks. The codec does **not** validate HMAC — secrets stay server-side in the Edge function.

**Architecture:** ChirpStack v4 expects `decodeUplink({fPort, bytes}) → {data}` and `encodeDownlink({fPort, data}) → {bytes}`. Both functions are pure synchronous JS, evaluated in a sandbox without `Buffer`. Tests run under Node with the same restrictions.

**Tech Stack:** Plain ES2020 JavaScript, no dependencies. Tests via `node --test`.

**Source spec:** `docs/superpowers/specs/2026-05-13-boatnode-hybrid-mesh-design.md` §"Backend Integration → ChirpStack codec".

---

## File Structure

| Path | Responsibility |
|---|---|
| `firmware/chirpstack/codec/mesh-codec.js` | The codec source pasted into ChirpStack UI |
| `firmware/chirpstack/codec/mesh-codec.test.mjs` | Node test runner |
| `firmware/chirpstack/codec/README.md` | Operator install notes |

---

## Task 1: Test harness + parseHeader

**Files:**
- Create: `firmware/chirpstack/codec/mesh-codec.js`
- Create: `firmware/chirpstack/codec/mesh-codec.test.mjs`

- [ ] **Step 1: Write failing test**

`mesh-codec.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeUplink } from "./mesh-codec.js";

test("decodeUplink POS extracts header fields", () => {
  const bytes = new Array(46).fill(0);
  bytes[0] = 0xba; bytes[1] = 0x02; bytes[2] = 0x01;
  bytes[3] = 0xf4; bytes[4] = 0x07;        // src 0x07f4
  bytes[5] = 0xff; bytes[6] = 0xff;        // dest broadcast
  bytes[7] = 0x05; bytes[8] = 0x00;        // seq 5
  bytes[9] = 0; bytes[10] = 4;
  bytes[11] = 0x40; bytes[12] = 0x2a; bytes[13] = 0x35; bytes[14] = 0x66;  // ts
  // crc is unverified by codec (Edge fn verifies). Leave as 0.
  const out = decodeUplink({ fPort: 1, bytes });
  assert.equal(out.data.header.type, 0x01);
  assert.equal(out.data.header.src, 0x07f4);
  assert.equal(out.data.header.seq, 5);
  assert.equal(out.data.framePayload, Buffer.from(bytes).toString("base64"));
});

test("decodeUplink rejects truncated frame", () => {
  const out = decodeUplink({ fPort: 1, bytes: [0xba, 0x02] });
  assert.equal(out.errors?.length > 0, true);
});

test("decodeUplink rejects bad magic", () => {
  const bytes = new Array(46).fill(0);
  bytes[0] = 0x00; bytes[1] = 0x02; bytes[2] = 0x01;
  const out = decodeUplink({ fPort: 1, bytes });
  assert.match(out.errors[0], /magic/);
});
```

- [ ] **Step 2: Run, fail**

Run: `cd firmware/chirpstack/codec && node --test mesh-codec.test.mjs`
Expected: FAIL — file not found.

- [ ] **Step 3: Implement codec**

`mesh-codec.js`:

```js
'use strict';

const MAGIC = 0xba;
const VER = 0x02;
const TYPES = { 0x01: 'POS', 0x02: 'SOS', 0x03: 'ACK', 0x04: 'CANCEL' };
const SIZES = { 0x01: 46, 0x02: 36, 0x03: 25, 0x04: 25 };

function u16le(b, o) { return b[o] | (b[o + 1] << 8); }
function u32le(b, o) { return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0; }

function b64encode(arr) {
  // ChirpStack JS runtime has Buffer available; fall back to manual otherwise.
  if (typeof Buffer !== 'undefined') return Buffer.from(arr).toString('base64');
  const alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = ''; let i = 0;
  while (i < arr.length) {
    const b0 = arr[i++] || 0, b1 = arr[i++] || 0, b2 = arr[i++] || 0;
    const t = (b0 << 16) | (b1 << 8) | b2;
    out += alpha[(t >> 18) & 63] + alpha[(t >> 12) & 63] +
           (i - 1 < arr.length ? alpha[(t >> 6) & 63] : '=') +
           (i < arr.length ? alpha[t & 63] : '=');
  }
  return out;
}

function decodeUplink(input) {
  const b = input.bytes;
  const errors = [];
  if (!b || b.length < 15) return { data: {}, errors: ['truncated'] };
  if (b[0] !== MAGIC) errors.push('magic');
  if (b[1] !== VER) errors.push('ver');
  const t = b[2];
  if (!SIZES[t]) errors.push('type');
  if (errors.length) return { data: {}, errors };
  if (b.length !== SIZES[t]) return { data: {}, errors: ['size'] };

  const header = {
    type: t, typeName: TYPES[t],
    src: u16le(b, 3), dest: u16le(b, 5), seq: u16le(b, 7),
    hops: b[9], ttl: b[10], ts: u32le(b, 11),
  };

  return {
    data: { header, framePayload: b64encode(b) },
  };
}

function encodeDownlink(input) {
  // Backend pre-builds ACK bytes server-side (HMAC there). Codec only relays.
  const bytes = input.data && input.data.bytes;
  if (!Array.isArray(bytes)) return { bytes: [], errors: ['expect data.bytes array'] };
  return { bytes };
}

if (typeof module !== 'undefined') module.exports = { decodeUplink, encodeDownlink };
```

- [ ] **Step 4: Run, pass**

Run: `node --test mesh-codec.test.mjs`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add firmware/chirpstack/codec/mesh-codec.js firmware/chirpstack/codec/mesh-codec.test.mjs
git commit -m "feat(chirpstack): codec parses mesh header and base64s frame for edge fn"
```

---

## Task 2: Operator README

**Files:**
- Create: `firmware/chirpstack/codec/README.md`

- [ ] **Step 1: Write operator notes**

`README.md`:

```markdown
# BoatNode Mesh Codec

Paste `mesh-codec.js` into ChirpStack v4 Application Server
**Application → Payload codecs → JavaScript functions**.

The codec parses the 15-byte mesh header and emits the full frame as
base64 in `data.framePayload`. The Edge function (`mesh-decoder`)
verifies HMAC and dispatches.

## Test before deploy

`node --test mesh-codec.test.mjs`

## Downlink shape

When the backend wants to send an ACK, POST to
`/api/devices/{devEui}/queue` with `data.bytes = [<25 byte AckPkt>]`.
The codec passes them through unchanged.
```

- [ ] **Step 2: Commit**

```bash
git add firmware/chirpstack/codec/README.md
git commit -m "docs(chirpstack): operator install notes"
```

---

## Spec coverage cross-check

| Spec § | Covered by |
|---|---|
| ChirpStack codec parses header, opaque payload | Task 1 |
| HMAC stays server-side | by design — codec never sees secrets |
| Downlink passthrough for ACK bytes | Task 1 `encodeDownlink` |
