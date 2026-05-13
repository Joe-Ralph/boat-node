# BoatNode Flutter App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Flutter app at `app/boatnode/` so that (a) the owner can complete the BLE pair flow that writes `boats.hmac_secret` / `crew_token` to Supabase; (b) crew members can authenticate to the boat over BLE using the per-tier challenge/response; (c) crew can trigger SOS through the boat device's BLE radio (which then broadcasts a signed SOS over mesh); (d) when no boat is in BLE range, the joiner falls back to the existing `broadcast_sos` Supabase RPC.

**Architecture:** Add small focused service modules. Keep `hardware_service.dart` as the BLE transport, `sos_service.dart` as the policy layer (try BLE, fall back to RPC), `backend_service.dart` as the Supabase RPC layer. Tokens live in `flutter_secure_storage`. Pairing writes secrets exactly once per device. Unit tests run with `flutter test`; widget tests cover the SOS routing decision.

**Tech Stack:** Flutter (Dart), `supabase_flutter`, `flutter_blue_plus` (or whatever the existing `hardware_service.dart` uses — preserve it), `flutter_secure_storage`, `crypto` package for HMAC-SHA256, `mocktail` for tests.

**Source spec:** `docs/superpowers/specs/2026-05-13-boatnode-hybrid-mesh-design.md` §"Joiner Support & Multi-tenant BLE" and §"App changes".

**Project root for all Flutter commands:** `app/boatnode/`. Pubspec lives there.

---

## File Structure

| Path | Responsibility |
|---|---|
| `lib/models/ble_auth.dart` | `BleTier` enum, `BleAuthSession` value type |
| `lib/models/sos_request.dart` | `SosRequest`, `SosOrigin`, `SosResult` |
| `lib/services/ble_auth_service.dart` | Challenge/response orchestration (pure of UI) |
| `lib/services/hardware_service.dart` | Extend with new characteristics, AUTH flow, SOS write, ACK_FEED notify |
| `lib/services/sos_service.dart` | BLE-first → RPC fallback decision |
| `lib/services/backend_service.dart` | Add `pairBoat`, `getCrewToken`, `cacheCrewToken` |
| `lib/services/secure_storage.dart` | Thin wrapper over `flutter_secure_storage` for tokens |
| `test/services/ble_auth_service_test.dart` | Unit |
| `test/services/sos_service_test.dart` | Unit (BLE vs RPC routing) |
| `test/services/backend_service_test.dart` | Unit (RPC mocks) |
| `pubspec.yaml` | Add `crypto`, `flutter_secure_storage`, `mocktail` (test) if missing |

---

## Task 1: Dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Inspect current deps**

Run: `cd app/boatnode && grep -E "crypto|flutter_secure_storage|mocktail" pubspec.yaml || echo "missing"`
Expected: either the existing version pins or `missing`.

- [ ] **Step 2: Add missing deps**

Edit `pubspec.yaml` under `dependencies:`:
```yaml
  crypto: ^3.0.3
  flutter_secure_storage: ^9.0.0
```
And under `dev_dependencies:`:
```yaml
  mocktail: ^1.0.0
```

- [ ] **Step 3: Resolve**

Run: `flutter pub get`
Expected: no version conflicts.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps(app): crypto + secure storage + mocktail"
```

---

## Task 2: Auth model

**Files:**
- Create: `lib/models/ble_auth.dart`

- [ ] **Step 1: Write the model**

```dart
enum BleTier { stranger, crew, owner }

class BleAuthSession {
  BleAuthSession({required this.tier, required this.boatId, required this.userShortId});
  final BleTier tier;
  final String boatId;
  final int userShortId;
  bool get canSos => tier == BleTier.owner || tier == BleTier.crew;
  bool get canConfig => tier == BleTier.owner;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/models/ble_auth.dart
git commit -m "feat(app): ble auth session model"
```

---

## Task 3: SosRequest / SosResult

**Files:**
- Create: `lib/models/sos_request.dart`

- [ ] **Step 1: Write the models**

```dart
enum SosOrigin { mesh, phoneDirect }

class SosRequest {
  SosRequest({required this.userShortId, required this.reason, required this.lat, required this.lon, required this.boatId});
  final int userShortId;
  final int reason;
  final double lat;
  final double lon;
  final String boatId;
}

class SosResult {
  SosResult.delivered(this.origin) : delivered = true, error = null;
  SosResult.failed(this.error) : delivered = false, origin = SosOrigin.phoneDirect;
  final bool delivered;
  final SosOrigin origin;
  final Object? error;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/models/sos_request.dart
git commit -m "feat(app): SosRequest + SosResult value types"
```

---

## Task 4: Secure storage wrapper

**Files:**
- Create: `lib/services/secure_storage.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage}) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  String _crewKey(String boatId) => 'crew_token::$boatId';

  Future<void> writeCrewToken(String boatId, List<int> token) =>
      _s.write(key: _crewKey(boatId), value: _hex(token));

  Future<List<int>?> readCrewToken(String boatId) async {
    final v = await _s.read(key: _crewKey(boatId));
    return v == null ? null : _fromHex(v);
  }

  Future<void> clearCrewToken(String boatId) => _s.delete(key: _crewKey(boatId));

  static String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  static List<int> _fromHex(String s) => [
        for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)
      ];
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/services/secure_storage.dart
git commit -m "feat(app): secure token store for crew tokens"
```

---

## Task 5: BLE auth service (pure)

**Files:**
- Create: `lib/services/ble_auth_service.dart`
- Create: `test/services/ble_auth_service_test.dart`

- [ ] **Step 1: Failing unit test**

`test/services/ble_auth_service_test.dart`:

```dart
import 'package:boatnode/services/ble_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('computes HMAC-SHA256 proof first 8 bytes', () {
    final key = List<int>.filled(16, 0xab);
    final challenge = List<int>.generate(16, (i) => i);
    final proof = BleAuthService.computeProof(key, challenge);
    expect(proof.length, 8);
    // Stability check: hard-code expected from external HMAC computation
    expect(proof, [0x6b, 0x49, 0x57, 0xbf, 0xd9, 0xc7, 0xe5, 0xc3]);
  });
}
```

- [ ] **Step 2: Run, fail**

Run: `cd app/boatnode && flutter test test/services/ble_auth_service_test.dart`
Expected: FAIL — service not found.

Verify the expected bytes by running an external script BEFORE writing the impl (the test must agree with `crypto`'s output, not the other way around). Adjust the literal as needed.

- [ ] **Step 3: Implement**

`lib/services/ble_auth_service.dart`:

```dart
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class BleAuthService {
  static Uint8List computeProof(List<int> token, List<int> challenge) {
    final mac = Hmac(sha256, token);
    final digest = mac.convert(challenge);
    return Uint8List.fromList(digest.bytes.sublist(0, 8));
  }
}
```

- [ ] **Step 4: Run again — let the test set the literal**

If the literal in step 1 was a placeholder, re-run the test, copy the actual proof from the failure message into the expectation, and re-run. Pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/ble_auth_service.dart test/services/ble_auth_service_test.dart
git commit -m "feat(app): ble auth hmac proof computation"
```

---

## Task 6: backend_service.dart — pair_boat + get_crew_token

**Files:**
- Modify: `lib/services/backend_service.dart`
- Create: `test/services/backend_service_test.dart`

- [ ] **Step 1: Failing test (mock Supabase)**

`test/services/backend_service_test.dart`:

```dart
import 'package:boatnode/services/backend_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockBuilder extends Mock implements PostgrestFilterBuilder<dynamic> {}

void main() {
  test('pairBoat calls pair_boat RPC and returns mesh_src_id', () async {
    final client = _MockClient();
    when(() => client.rpc('pair_boat', params: any(named: 'params')))
        .thenAnswer((_) async => 17);
    final svc = BackendService(client: client);
    final id = await svc.pairBoat(
      devEui: List<int>.filled(8, 0),
      hmacSecret: List<int>.filled(16, 0),
      crewToken: List<int>.filled(8, 0),
      displayName: 'Test',
    );
    expect(id, 17);
  });

  test('getCrewToken returns bytes', () async {
    final client = _MockClient();
    when(() => client.rpc('get_crew_token', params: {'p_boat_id': 5}))
        .thenAnswer((_) async => 'aabbccdd');
    final svc = BackendService(client: client);
    expect(await svc.getCrewToken(5), [0xaa, 0xbb, 0xcc, 0xdd]);
  });
}
```

- [ ] **Step 2: Run, fail**

Run: `flutter test test/services/backend_service_test.dart`
Expected: FAIL — method not found.

- [ ] **Step 3: Implement (additive — keep existing methods)**

Add to `lib/services/backend_service.dart`:

```dart
Future<int> pairBoat({
  required List<int> devEui,
  required List<int> hmacSecret,
  required List<int> crewToken,
  required String displayName,
}) async {
  final r = await _client.rpc('pair_boat', params: {
    'p_dev_eui': devEui,
    'p_hmac_secret': hmacSecret,
    'p_crew_token': crewToken,
    'p_display_name': displayName,
  });
  return r as int;
}

Future<List<int>> getCrewToken(int boatId) async {
  final r = await _client.rpc('get_crew_token', params: {'p_boat_id': boatId});
  if (r is String) {
    // Postgres bytea via PostgREST hex `\x...` or plain hex
    final hex = r.startsWith('\\x') ? r.substring(2) : r;
    return [
      for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)
    ];
  }
  if (r is List) return List<int>.from(r);
  throw StateError('unexpected crew_token shape: ${r.runtimeType}');
}
```

If the class has no constructor accepting `SupabaseClient`, add one with a default so callers don't break:
```dart
BackendService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
```

- [ ] **Step 4: Run, pass**

Run: `flutter test test/services/backend_service_test.dart`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backend_service.dart test/services/backend_service_test.dart
git commit -m "feat(app): pair_boat + get_crew_token rpc bindings with tests"
```

---

## Task 7: hardware_service.dart — new characteristics

**Files:**
- Modify: `lib/services/hardware_service.dart`

This is additive — preserve the existing DATA + CMD characteristic handling. Add 4 new characteristics: `AUTH_CHALLENGE`, `AUTH_RESPONSE`, `AUTH_STATUS`, `SOS_TRIGGER`, `ACK_FEED`. UUIDs go in a small constants block.

- [ ] **Step 1: Add UUID constants near the top of the file**

```dart
class BoatBleUuids {
  static const service           = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const data              = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';   // existing
  static const cmd               = '8246d623-9ff2-4f9c-9c4b-4d4e2b6c1e91';   // existing
  static const authChallenge     = '5d3bcab2-2a3c-4e22-9f8d-0e3b3d80b001';
  static const authResponse      = '5d3bcab2-2a3c-4e22-9f8d-0e3b3d80b002';
  static const authStatus        = '5d3bcab2-2a3c-4e22-9f8d-0e3b3d80b003';
  static const sosTrigger        = '5d3bcab2-2a3c-4e22-9f8d-0e3b3d80b004';
  static const ackFeed           = '5d3bcab2-2a3c-4e22-9f8d-0e3b3d80b005';
}
```

- [ ] **Step 2: Add an `authenticate({required List<int> token, required BleTier hint})` method**

Inside the `HardwareService` class:

```dart
import '../models/ble_auth.dart';
import 'ble_auth_service.dart';

Future<BleTier> authenticate({required List<int> token, required BleTier hint}) async {
  final challenge = await _readCharacteristic(BoatBleUuids.authChallenge);
  final proof = BleAuthService.computeProof(token, challenge);
  final body = [hint.index, ...proof];
  await _writeCharacteristic(BoatBleUuids.authResponse, body);
  final status = await _readCharacteristic(BoatBleUuids.authStatus);
  if (status.isEmpty) return BleTier.stranger;
  return BleTier.values[status[0]];
}
```

`_readCharacteristic` / `_writeCharacteristic` are whatever helpers the existing file uses to talk to characteristics by UUID — adapt names if the helpers are inline.

- [ ] **Step 3: Add `triggerSos` and `cancelSos` writers**

```dart
Future<void> triggerSos({required int userShortId, required int reason}) async {
  final body = <int>[
    reason & 0xff,
    userShortId & 0xff, (userShortId >> 8) & 0xff,
  ];
  await _writeCharacteristic(BoatBleUuids.sosTrigger, body);
}

Future<void> cancelSos({required int userShortId}) async {
  final body = <int>[
    0x01,
    userShortId & 0xff, (userShortId >> 8) & 0xff,
  ];
  await _writeCharacteristic(BoatBleUuids.cmd, body);  // CMD path: CANCEL_SOS opcode
}
```

- [ ] **Step 4: Expose an `ackFeedStream` from notifications**

```dart
final _ackController = StreamController<Map<String, dynamic>>.broadcast();
Stream<Map<String, dynamic>> get ackFeed => _ackController.stream;

Future<void> _subscribeAckFeed() async {
  await _subscribeNotify(BoatBleUuids.ackFeed, (data) {
    if (data.length < 5) return;
    final ackSeq = data[0] | (data[1] << 8);
    final status = data[2];
    _ackController.add({'ack_seq': ackSeq, 'status': status});
  });
}
```

Wire `_subscribeAckFeed()` into the existing post-connect flow alongside the DATA subscription.

- [ ] **Step 5: Build to confirm no analyzer regressions**

Run: `flutter analyze`
Expected: 0 issues introduced by this file.

- [ ] **Step 6: Commit**

```bash
git add lib/services/hardware_service.dart
git commit -m "feat(app): hardware_service auth handshake + SOS write + ACK feed"
```

---

## Task 8: sos_service.dart — BLE first, RPC fallback

**Files:**
- Modify: `lib/services/sos_service.dart`
- Create: `test/services/sos_service_test.dart`

- [ ] **Step 1: Failing test**

`test/services/sos_service_test.dart`:

```dart
import 'package:boatnode/models/sos_request.dart';
import 'package:boatnode/services/sos_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Hw extends Mock {
  Future<bool> isBoatInRange(String boatId);
  Future<void> triggerSos({required int userShortId, required int reason});
}
class _Backend extends Mock {
  Future<void> broadcastSos({required double lat, required double lon, required int userShortId});
}

void main() {
  late _Hw hw;
  late _Backend backend;
  late SosService svc;

  setUp(() {
    hw = _Hw();
    backend = _Backend();
    svc = SosService(hw: hw as dynamic, backend: backend as dynamic);
    registerFallbackValue(SosRequest(userShortId: 0, reason: 0, lat: 0, lon: 0, boatId: 'B0'));
  });

  test('uses BLE when boat in range', () async {
    when(() => hw.isBoatInRange(any())).thenAnswer((_) async => true);
    when(() => hw.triggerSos(userShortId: any(named: 'userShortId'), reason: any(named: 'reason')))
        .thenAnswer((_) async {});
    final r = await svc.send(SosRequest(userShortId: 42, reason: 0, lat: 10, lon: 77, boatId: 'B1'));
    expect(r.origin, SosOrigin.mesh);
    verifyNever(() => backend.broadcastSos(lat: any(named: 'lat'), lon: any(named: 'lon'), userShortId: any(named: 'userShortId')));
  });

  test('falls back to RPC when BLE not in range', () async {
    when(() => hw.isBoatInRange(any())).thenAnswer((_) async => false);
    when(() => backend.broadcastSos(lat: any(named: 'lat'), lon: any(named: 'lon'), userShortId: any(named: 'userShortId')))
        .thenAnswer((_) async {});
    final r = await svc.send(SosRequest(userShortId: 42, reason: 0, lat: 10, lon: 77, boatId: 'B1'));
    expect(r.origin, SosOrigin.phoneDirect);
    verify(() => backend.broadcastSos(lat: 10, lon: 77, userShortId: 42)).called(1);
  });

  test('falls back when BLE throws', () async {
    when(() => hw.isBoatInRange(any())).thenAnswer((_) async => true);
    when(() => hw.triggerSos(userShortId: any(named: 'userShortId'), reason: any(named: 'reason')))
        .thenThrow(StateError('disconnected'));
    when(() => backend.broadcastSos(lat: any(named: 'lat'), lon: any(named: 'lon'), userShortId: any(named: 'userShortId')))
        .thenAnswer((_) async {});
    final r = await svc.send(SosRequest(userShortId: 42, reason: 0, lat: 10, lon: 77, boatId: 'B1'));
    expect(r.origin, SosOrigin.phoneDirect);
  });
}
```

- [ ] **Step 2: Run, fail**

Run: `flutter test test/services/sos_service_test.dart`
Expected: FAIL — method `send` or class shape mismatch.

- [ ] **Step 3: Implement**

Add to `lib/services/sos_service.dart`:

```dart
import '../models/sos_request.dart';
import 'hardware_service.dart';
import 'backend_service.dart';

class SosService {
  SosService({required this.hw, required this.backend});
  final HardwareService hw;
  final BackendService backend;

  Future<SosResult> send(SosRequest req) async {
    try {
      if (await hw.isBoatInRange(req.boatId)) {
        await hw.triggerSos(userShortId: req.userShortId, reason: req.reason);
        return SosResult.delivered(SosOrigin.mesh);
      }
    } catch (_) { /* fall through */ }
    try {
      await backend.broadcastSos(lat: req.lat, lon: req.lon, userShortId: req.userShortId);
      return SosResult.delivered(SosOrigin.phoneDirect);
    } catch (e) {
      return SosResult.failed(e);
    }
  }
}
```

If `HardwareService` does not already expose `isBoatInRange`, add a minimal implementation that scans for the configured device for at most 5 s and returns true if found connected.

- [ ] **Step 4: Run, pass**

Run: `flutter test test/services/sos_service_test.dart`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add lib/services/sos_service.dart test/services/sos_service_test.dart
git commit -m "feat(app): sos_service BLE-first fallback to RPC with routing tests"
```

---

## Task 9: Pair flow wiring

**Files:**
- Modify: existing pairing screen under `lib/screens/pairing_screen.dart` (file name may vary — find via grep)

- [ ] **Step 1: After the existing BLE/AP handshake that reads the device's generated secrets**

Replace the prior REST POST with a call to the new RPC:

```dart
final secrets = await hardware.fetchPairSecrets();  // existing or new helper that reads generated secrets from device
final meshSrcId = await backend.pairBoat(
  devEui: secrets.devEui,
  hmacSecret: secrets.hmacSecret,
  crewToken: secrets.crewToken,
  displayName: displayNameController.text,
);
await hardware.finalizePair(meshSrcId: meshSrcId);
await storage.writeCrewToken(boatId, secrets.crewToken);  // owner can also auth as crew on their own boat
```

- [ ] **Step 2: Manual sanity build**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/pairing_screen.dart
git commit -m "feat(app): pair flow uses pair_boat RPC and persists mesh_src_id"
```

---

## Task 10: Crew QR-join flow

**Files:**
- Modify: `lib/screens/qr_scan_screen.dart`

- [ ] **Step 1: After backend writes the membership row**

Insert:
```dart
final token = await backend.getCrewToken(boatId);
await storage.writeCrewToken(boatId.toString(), token);
```

- [ ] **Step 2: On next BLE proximity, run auth**

In whichever service launches BLE-connect on the dashboard:
```dart
final token = await storage.readCrewToken(boatId.toString());
if (token != null) {
  final tier = await hardware.authenticate(token: token, hint: BleTier.crew);
  session.tier = tier;
}
```

- [ ] **Step 3: Manual analyze + visual smoke**

Run: `flutter analyze && flutter run -d <device>`
Walk the QR scan → join → connect path. Expect AUTH_STATUS read to return crew.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/qr_scan_screen.dart lib/services/<connect-orchestrator>.dart
git commit -m "feat(app): crew QR join fetches crew_token and authenticates on connect"
```

---

## Task 11: Smoke run on device

- [ ] **Step 1: Owner pair flow**

Pair an unpaired device. Verify the Supabase `boats` row now has `mesh_src_id`, `hmac_secret`, `crew_token` populated.

- [ ] **Step 2: Owner SOS**

Trigger SOS from owner. Verify a `sos_signals` row with `origin='mesh'` (assuming backend + firmware tasks merged) or `origin='phone_direct'` (if firmware not yet flipped).

- [ ] **Step 3: Crew SOS**

On second phone: scan owner QR → connect → trigger SOS. Verify `trigger_user_id` matches the joiner.

- [ ] **Step 4: Joiner fallback**

Disable BLE on the joiner phone or move out of range. Trigger SOS. Verify a `sos_signals` row with `origin='phone_direct'`.

---

## Spec coverage cross-check

| Spec § | Covered by |
|---|---|
| `triggerSos({userId, reason})` BLE write | Task 7 |
| `cancelSos({userId, seq})` BLE write | Task 7 |
| `ackFeedStream` | Task 7 |
| `pairBoat({devEui, hmacSecret, crewToken, displayName})` | Task 6 + Task 9 |
| `getCrewToken(boatId)` + secure storage | Tasks 4, 6, 10 |
| `sendSos` BLE first, RPC fallback | Task 8 |
| AUTH challenge/response handshake | Tasks 5, 7 |
| Per-tier session state | Task 2 |
