# BoatNode Admin Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the SOS surface of the admin dashboard mesh-aware. After schema v10 lands, `sos_signals` rows carry `origin`, `gateway_boat_id`, `mesh_hops`, `trigger_user_id`, `trigger_user_short_id`, `ack_status`, `acked_at`. The dashboard must display all of those, let a dispatcher mark a signal **resolved** or **false-alarm**, and (when triggered) post an ACK downlink through the Edge function.

**Architecture:** Additive changes to the existing Next.js 16 App-Router project at `admin/`. New route `/sos/[id]` for the detail drawer; existing `/sos` list view gets an `origin` badge column. Server components fetch through `utils/supabase/server.ts`; mutations call a small Route Handler that wraps a Supabase Edge function POST so secrets never touch the browser.

**Tech Stack:** Next.js 16 (App Router), React 19, TypeScript, Supabase SSR, Tailwind (existing). Tests via `vitest`.

**Source spec:** `docs/superpowers/specs/2026-05-13-boatnode-hybrid-mesh-design.md` §"Admin dashboard" bullets.

---

## File Structure

| Path | Responsibility |
|---|---|
| `admin/lib/types/sos.ts` | Shared types (`SosSignal`, `AckStatus`) |
| `admin/lib/queries/sos.ts` | Supabase fetchers (server-only) |
| `admin/app/(dashboard)/sos/page.tsx` | List view — add origin badge, hops, gateway |
| `admin/app/(dashboard)/sos/[id]/page.tsx` | Detail page with resolve / false-alarm buttons |
| `admin/components/sos/OriginBadge.tsx` | Visual cue (mesh vs phone_direct) |
| `admin/components/sos/AckPanel.tsx` | Status + action client component |
| `admin/app/api/sos/[id]/ack/route.ts` | POST → mark ack_status + invoke Edge fn downlink |
| `admin/lib/edge-client.ts` | Service-role caller to mesh-decoder Edge fn |
| `admin/tests/sos.test.ts` | vitest for query shape + handler logic |

---

## Task 1: Shared SOS type

**Files:**
- Create: `admin/lib/types/sos.ts`

- [ ] **Step 1: Write the type**

```ts
export type SosOrigin = 'mesh' | 'phone_direct';
export type AckStatus = 0 | 1 | 2 | 3;  // 0 received, 1 dispatched, 2 resolved, 3 false-alarm

export interface SosSignal {
  id: number;
  boat_id: number;
  origin: SosOrigin;
  status: 'active' | 'canceled' | 'resolved' | 'false_alarm';
  lat: number;
  lon: number;
  reason: number;
  mesh_seq: number | null;
  mesh_hops: number | null;
  gateway_boat_id: number | null;
  trigger_user_id: string | null;
  trigger_user_short_id: number | null;
  ack_status: AckStatus;
  acked_at: string | null;
  created_at: string;
}

export const ACK_LABEL: Record<AckStatus, string> = {
  0: 'received',
  1: 'dispatched',
  2: 'resolved',
  3: 'false alarm',
};
```

- [ ] **Step 2: Commit**

```bash
git add admin/lib/types/sos.ts
git commit -m "feat(admin): shared SosSignal types"
```

---

## Task 2: Origin badge component

**Files:**
- Create: `admin/components/sos/OriginBadge.tsx`

- [ ] **Step 1: Implement**

```tsx
import type { SosOrigin } from '@/lib/types/sos';

const STYLES: Record<SosOrigin, { label: string; cls: string }> = {
  mesh:         { label: 'MESH',   cls: 'bg-cyan-500/10 text-cyan-300 border-cyan-500/40' },
  phone_direct: { label: 'DIRECT', cls: 'bg-amber-500/10 text-amber-300 border-amber-500/40' },
};

export function OriginBadge({ origin }: { origin: SosOrigin }) {
  const s = STYLES[origin];
  return (
    <span className={`inline-flex items-center px-2 py-0.5 text-[10px] font-mono tracking-widest border ${s.cls}`}>
      {s.label}
    </span>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add admin/components/sos/OriginBadge.tsx
git commit -m "feat(admin): origin badge component"
```

---

## Task 3: Server query

**Files:**
- Create: `admin/lib/queries/sos.ts`

- [ ] **Step 1: Implement**

```ts
import 'server-only';
import { createServerClient } from '@/utils/supabase/server';
import type { SosSignal } from '@/lib/types/sos';

export async function listActiveSos(): Promise<SosSignal[]> {
  const sb = await createServerClient();
  const { data, error } = await sb
    .from('sos_signals')
    .select('id, boat_id, origin, status, lat, lon, reason, mesh_seq, mesh_hops, gateway_boat_id, trigger_user_id, trigger_user_short_id, ack_status, acked_at, created_at')
    .in('status', ['active', 'canceled'])
    .order('created_at', { ascending: false })
    .limit(200);
  if (error) throw error;
  return (data ?? []) as SosSignal[];
}

export async function getSos(id: number): Promise<SosSignal | null> {
  const sb = await createServerClient();
  const { data, error } = await sb
    .from('sos_signals').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return (data as SosSignal | null);
}
```

- [ ] **Step 2: Commit**

```bash
git add admin/lib/queries/sos.ts
git commit -m "feat(admin): server query helpers for sos_signals"
```

---

## Task 4: List page — origin column + hops + gateway

**Files:**
- Modify: `admin/app/(dashboard)/sos/page.tsx`

- [ ] **Step 1: Replace the row template**

Within the existing `<table>` body, render each row with the new columns:

```tsx
import { OriginBadge } from '@/components/sos/OriginBadge';
import { listActiveSos } from '@/lib/queries/sos';
import { ACK_LABEL } from '@/lib/types/sos';
import Link from 'next/link';

export default async function SosPage() {
  const rows = await listActiveSos();
  return (
    <div className="p-6">
      <h1 className="font-mono text-xs tracking-[0.3em] text-zinc-500 mb-4">ACTIVE SOS · {rows.length}</h1>
      <table className="w-full text-sm">
        <thead className="text-[10px] tracking-[0.25em] uppercase text-zinc-500">
          <tr>
            <th className="text-left py-2">Boat</th>
            <th className="text-left">Origin</th>
            <th className="text-left">Hops</th>
            <th className="text-left">Gateway</th>
            <th className="text-left">Trigger user</th>
            <th className="text-left">ACK</th>
            <th className="text-left">When</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id} className="border-t border-zinc-800 hover:bg-zinc-900/40">
              <td className="py-2"><Link className="underline" href={`/sos/${r.id}`}>#{r.boat_id}</Link></td>
              <td><OriginBadge origin={r.origin} /></td>
              <td className="font-mono text-xs">{r.mesh_hops ?? '—'}</td>
              <td className="font-mono text-xs">{r.gateway_boat_id ?? '—'}</td>
              <td className="font-mono text-xs">{r.trigger_user_short_id ?? '—'}</td>
              <td className="font-mono text-xs">{ACK_LABEL[r.ack_status]}</td>
              <td className="font-mono text-xs">{new Date(r.created_at).toLocaleString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

- [ ] **Step 2: Build to confirm**

Run: `cd admin && npm run build`
Expected: SUCCESS, no type errors.

- [ ] **Step 3: Commit**

```bash
git add admin/app/(dashboard)/sos/page.tsx
git commit -m "feat(admin): sos list now shows origin, hops, gateway, trigger user"
```

---

## Task 5: Edge client (service-role)

**Files:**
- Create: `admin/lib/edge-client.ts`

- [ ] **Step 1: Implement**

```ts
import 'server-only';

interface AckTriggerArgs { sosId: number; status: 2 | 3 }

export async function triggerAckDownlink({ sosId, status }: AckTriggerArgs): Promise<void> {
  const url = `${process.env.SUPABASE_URL}/functions/v1/mesh-decoder-ack`;
  const r = await fetch(url, {
    method: 'POST',
    headers: {
      'authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ sos_id: sosId, status }),
  });
  if (!r.ok) throw new Error(`ack downlink failed: ${r.status} ${await r.text()}`);
}
```

> **Note:** This depends on a complementary `mesh-decoder-ack` Edge function endpoint that loads the SOS row, builds an `AckPkt` with `pgcrypto.hmac` + the originator's `hmac_secret`, and POSTs to ChirpStack. Track that work under the backend plan as a v10.1 follow-up if the v10 backend deploy is already cut.

- [ ] **Step 2: Commit**

```bash
git add admin/lib/edge-client.ts
git commit -m "feat(admin): edge-client triggerAckDownlink"
```

---

## Task 6: Route handler — mark resolved / false-alarm

**Files:**
- Create: `admin/app/api/sos/[id]/ack/route.ts`
- Create: `admin/tests/sos.test.ts`

- [ ] **Step 1: Failing test**

`admin/tests/sos.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest';
import { POST } from '@/app/api/sos/[id]/ack/route';

vi.mock('@/utils/supabase/server', () => ({
  createServerClient: async () => ({
    from: () => ({
      update: () => ({
        eq: () => ({ select: () => ({ maybeSingle: async () => ({ data: { id: 7 }, error: null }) }) }),
      }),
    }),
  }),
}));
vi.mock('@/lib/edge-client', () => ({ triggerAckDownlink: vi.fn(async () => {}) }));

describe('POST /api/sos/:id/ack', () => {
  it('200s on resolved', async () => {
    const req = new Request('http://x/', { method: 'POST', body: JSON.stringify({ status: 2 }) });
    const res = await POST(req, { params: Promise.resolve({ id: '7' }) });
    expect(res.status).toBe(200);
  });
  it('400s on bad status', async () => {
    const req = new Request('http://x/', { method: 'POST', body: JSON.stringify({ status: 9 }) });
    const res = await POST(req, { params: Promise.resolve({ id: '7' }) });
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: Run, fail**

Run: `cd admin && npx vitest run tests/sos.test.ts`
Expected: FAIL — route not found.

- [ ] **Step 3: Implement**

`admin/app/api/sos/[id]/ack/route.ts`:

```ts
import { NextResponse } from 'next/server';
import { createServerClient } from '@/utils/supabase/server';
import { triggerAckDownlink } from '@/lib/edge-client';

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id: rawId } = await ctx.params;
  const id = Number(rawId);
  if (!Number.isFinite(id)) return NextResponse.json({ error: 'bad id' }, { status: 400 });

  const body = await req.json().catch(() => null) as { status?: number } | null;
  const status = body?.status;
  if (status !== 2 && status !== 3) return NextResponse.json({ error: 'bad status' }, { status: 400 });

  const sb = await createServerClient();
  const final = status === 2 ? 'resolved' : 'false_alarm';
  const { data, error } = await sb.from('sos_signals')
    .update({ ack_status: status, acked_at: new Date().toISOString(), status: final })
    .eq('id', id)
    .select('id')
    .maybeSingle();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  if (!data) return NextResponse.json({ error: 'not found' }, { status: 404 });

  await triggerAckDownlink({ sosId: id, status: status as 2 | 3 });
  return NextResponse.json({ ok: true });
}
```

- [ ] **Step 4: Run, pass**

Run: `npx vitest run tests/sos.test.ts`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add admin/app/api/sos/[id]/ack/route.ts admin/tests/sos.test.ts
git commit -m "feat(admin): ack route to mark resolved/false-alarm + downlink"
```

---

## Task 7: AckPanel client component

**Files:**
- Create: `admin/components/sos/AckPanel.tsx`

- [ ] **Step 1: Implement**

```tsx
'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { ACK_LABEL, type AckStatus } from '@/lib/types/sos';

export function AckPanel({ sosId, current }: { sosId: number; current: AckStatus }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function mark(status: 2 | 3) {
    if (busy) return;
    if (!confirm(`Mark SOS #${sosId} as ${ACK_LABEL[status]}? This sends an ACK to the boat.`)) return;
    setBusy(true); setErr(null);
    try {
      const r = await fetch(`/api/sos/${sosId}/ack`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ status }),
      });
      if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
      router.refresh();
    } catch (e) {
      setErr((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="border border-zinc-800 p-4">
      <div className="text-[10px] font-mono tracking-widest text-zinc-500 mb-3">CURRENT · {ACK_LABEL[current].toUpperCase()}</div>
      <div className="flex gap-2">
        <button onClick={() => mark(2)} disabled={busy}
          className="px-3 py-1.5 font-mono text-xs tracking-widest uppercase border border-emerald-500/50 text-emerald-300 hover:bg-emerald-500/10 disabled:opacity-50">
          Mark resolved
        </button>
        <button onClick={() => mark(3)} disabled={busy}
          className="px-3 py-1.5 font-mono text-xs tracking-widest uppercase border border-amber-500/50 text-amber-300 hover:bg-amber-500/10 disabled:opacity-50">
          Mark false alarm
        </button>
      </div>
      {err && <div className="mt-2 text-xs text-red-400 font-mono">{err}</div>}
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add admin/components/sos/AckPanel.tsx
git commit -m "feat(admin): ack panel client component with confirm + refresh"
```

---

## Task 8: Detail page

**Files:**
- Create: `admin/app/(dashboard)/sos/[id]/page.tsx`

- [ ] **Step 1: Implement**

```tsx
import { notFound } from 'next/navigation';
import { getSos } from '@/lib/queries/sos';
import { OriginBadge } from '@/components/sos/OriginBadge';
import { AckPanel } from '@/components/sos/AckPanel';
import { ACK_LABEL } from '@/lib/types/sos';

export default async function SosDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const sos = await getSos(Number(id));
  if (!sos) notFound();

  return (
    <div className="p-6 grid grid-cols-1 lg:grid-cols-[1fr_320px] gap-8">
      <div>
        <div className="flex items-center gap-3 mb-2">
          <h1 className="font-mono text-xs tracking-[0.3em] text-zinc-500">SOS · #{sos.id} · BOAT {sos.boat_id}</h1>
          <OriginBadge origin={sos.origin} />
        </div>
        <dl className="grid grid-cols-2 gap-y-2 gap-x-8 mt-6 text-sm">
          <dt className="text-zinc-500 font-mono text-xs">lat / lon</dt><dd className="font-mono">{sos.lat}, {sos.lon}</dd>
          <dt className="text-zinc-500 font-mono text-xs">reason</dt><dd className="font-mono">{sos.reason}</dd>
          <dt className="text-zinc-500 font-mono text-xs">mesh seq</dt><dd className="font-mono">{sos.mesh_seq ?? '—'}</dd>
          <dt className="text-zinc-500 font-mono text-xs">mesh hops</dt><dd className="font-mono">{sos.mesh_hops ?? '—'}</dd>
          <dt className="text-zinc-500 font-mono text-xs">gateway boat</dt><dd className="font-mono">{sos.gateway_boat_id ?? '—'}</dd>
          <dt className="text-zinc-500 font-mono text-xs">trigger user</dt><dd className="font-mono">{sos.trigger_user_short_id ?? '—'} ({sos.trigger_user_id ?? 'unknown'})</dd>
          <dt className="text-zinc-500 font-mono text-xs">ack</dt><dd className="font-mono">{ACK_LABEL[sos.ack_status]}</dd>
          <dt className="text-zinc-500 font-mono text-xs">received at</dt><dd className="font-mono">{new Date(sos.created_at).toLocaleString()}</dd>
        </dl>
      </div>
      <AckPanel sosId={sos.id} current={sos.ack_status} />
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add admin/app/(dashboard)/sos/[id]/page.tsx
git commit -m "feat(admin): sos detail page with ack panel"
```

---

## Task 9: Smoke flow

- [ ] **Step 1: Run dev server**

Run: `cd admin && npm run dev`
Expected: server boots on http://localhost:3000.

- [ ] **Step 2: Walk the path**

1. Insert a fake mesh SOS in Supabase via SQL editor:
   ```sql
   INSERT INTO sos_signals (boat_id, origin, status, lat, lon, reason, mesh_seq, mesh_hops, gateway_boat_id)
   VALUES (1, 'mesh', 'active', 10.0, 77.0, 0, 42, 2, 1);
   ```
2. Visit `/sos`. Verify `MESH` badge, `hops=2`, `gateway=1`.
3. Click the row, land on `/sos/<id>`.
4. Click "Mark resolved". Confirm dialog. After the request:
   - row's `ack_status` becomes 2, `status` becomes `resolved`, `acked_at` set.
   - Edge fn call attempts a downlink (will 502 if the v10.1 endpoint is not yet deployed — surface to the operator, not a blocker for this UI).

- [ ] **Step 3: No commit unless smoke required changes.**

---

## Spec coverage cross-check

| Spec § | Covered by |
|---|---|
| Show `origin` | Task 2, 4 |
| Show `gateway_boat_id`, `mesh_hops`, `trigger_user_id` | Task 4, 8 |
| "Mark resolved" / "Mark false alarm" buttons | Tasks 6, 7, 8 |
| ACK downlink trigger with status=2/3 | Tasks 5, 6 (Edge fn endpoint tracked as v10.1) |
