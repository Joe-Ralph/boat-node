# site3d Redesign Spec

> Source of truth for the site3d redesign. Each phase may be executed in a fresh context window — read this doc first. Cross-references: original plan at `/Users/joe/.claude/plans/composed-wibbling-canyon.md`.

## Context

`site3d/` is the marketing landing site for **Neduvaai / BoatNode** (fisherman-safety hybrid LoRaWAN+mesh system). Stack: Vite + React 19 + Three.js 0.160 + GSAP 3.14 (ScrollTrigger) + TypeScript 5.8. Hash-routed: `#/` = scroll story (`App.tsx`), `#/docs` = technical docs (`components/Docs.tsx`).

### Problems being fixed
1. Acts 1 & 2 visually identical (boat translates +x, camera follows) — narrative flatlines.
2. SOS climax feels mechanical, not emotional.
3. "Neduvaai Activates" plays celebratory when it should feel earned.
4. Section 4 is a disembodied text-only CTA card — no real conversion path.
5. `App.tsx` is a 1,273-line monolith.
6. `Docs.tsx` (1,797L) orphaned from story — no narrative bridge.
7. Dead code: `Hero.tsx`, `InputArea.tsx`, `LivePreview.tsx`, `CreationHistory.tsx`, `services/gemini.ts`, `services/firebase.ts`.
8. Tailwind via CDN despite local `@tailwind` directives in `index.css` (never processed).
9. No audio, no scroll-velocity reactivity, no parallax.
10. No `prefers-reduced-motion` fallback.

### Locked decisions (from brainstorming)
- Goals: **emotional impact + conversion** (tech credibility deferred to `#/docs`).
- Scope: **full rebuild with audio + interaction + a11y fallback**.
- Orphans: **deleted**.
- New accent: warm amber `#FFB347` for harbor lamps, family windows, dawn shift.
- Audio: **CC0** sources (Freesound, Pixabay Music) + Web Audio synthesis.
- CTA destinations: **placeholders** (`mailto:hello@example.com`, `https://github.com/USER/REPO`, newsletter TODO).
- Reduced-motion: **full static fallback** (7 cards, no audio).

## Narrative (7 acts, ~110s scroll)

| # | Act | ~Dur | 3D state | Copy | Audio | Interaction |
|---|---|---|---|---|---|---|
| 0 | **Invocation** | 10s | Existing `LandingOverlay` particle yarn-ball + gravitational lens | "Ever wondered how the fish on your plate reaches you? Someone risks their life for it." | Harbor ambience -18dB | Mouse warps lens |
| 1 | **Departure** | 15s | Boat at x=-8, amber lamp `#FFB347`, dawn-tint surface, tower pulses cyan, harbor-light sprites | "Before dawn, someone leaves for work." | Engine diesel, gull, Cmaj7 pad, hull water | Parallax 0.6×, bow spray on scroll velocity |
| 2 | **Beyond Signal** | 15s | Tower fades, shoreline fades, ocean cyan→ultramarine, wave 0.25→0.9, signal arcs snap & dissolve | "The shore goes quiet. / No bars. No signal. No one knows where he is." | Engine+reverb up, wind, radio-static burst, music detunes −30¢ | Scroll velocity → wave height |
| 3 | **The Storm** *(new)* | 15s | Wave 0.9→1.6, rain particles, sky `#050810`, boat pitch ×1.8, camera shake | "Then the sea forgets him." | Rain on deck, wind peak, thunder sub-bass, pad → minor 9 | Scroll-velocity → rain density; parallax polarity flipped |
| 4 | **SOS** | 12s | Boat → red, SOS pulse sphere on Morse rhythm (· · · — — — · · ·), 4 mesh boats DARK | "And no one is coming." (red, JetBrains Mono uppercase) | Near-silence + ECG-sync beep + wind bed | Parallax locked off; SOS rhythm immutable |
| 5 | **Neduvaai Wakes** | 18s | Mesh boats light cyan one at a time (1s gaps), chain draws 50% slower, tower re-lights only when chain arrives; boat red → violet `#D54DFF` on relay | "Boat to boat. / Node to node. / Shore to family." | Cyan ping per hop (synth), pad retunes, ECG resolves to sustain | Parallax returns gentle, scroll velocity nudges hop timing |
| 6 | **Home** | 12s | Bird's-eye harbor, all mesh boats cyan, SOS boat violet, tower steady, warm amber window-lights, dawn peach | "This is Neduvaai. / A mesh that doesn't forget anyone." | Cmaj7 resolution, harbor bells, gulls | Full parallax; yarn-ball callback rings wordmark |
| 7 | **Act** | 15s | Harbor at 30% opacity behind translucent CTA panel | — | Pad sustains | CTA panel + docs-bridge link; parallax persists |

## Target architecture

```
site3d/
  engine/
    Engine.tsx              # Canvas + renderer + scene + camera + rAF loop; EngineContext provider
    EngineContext.ts        # type SceneSystem = { update(dt,t,scrollProgress): void; dispose(): void }
    CameraRig.ts            # base pose + dolly + shake + parallax composition
    Loader.ts               # async asset preloader (audio buffers); progress callback
    utils/
      createLowPolyBoat.ts  # extract from App.tsx:16–89
      createOcean.ts        # extract; uses shaders.ts
      createTower.ts        # extract from App.tsx:297–463
      createTerrain.ts      # extract from App.tsx:167–290
      createMeshBoats.ts    # extract ambient mesh + signal rings
      createSignalArcs.ts   # NEW: snapping arcs for Act 2
      createRain.ts         # NEW: rain particles for Act 3
      createHarborLights.ts # NEW: amber sprites for Acts 1 & 6
  scenes/
    SceneRegistry.ts        # master timeline orchestrator
    InvocationScene.tsx     # Act 0
    DepartureScene.ts       # Act 1
    BeyondSignalScene.ts    # Act 2
    StormScene.ts           # Act 3
    SOSScene.ts             # Act 4
    AwakeningScene.ts       # Act 5
    HomeScene.ts            # Act 6
    ActScene.tsx            # Act 7
  audio/
    AudioGraph.ts           # AudioContext + masterGain + music/ambience/sfx buses w/ Gain→Convolver
    AmbientBed.ts           # looped sources w/ setLayerVolume
    SfxPlayer.ts            # one-shots: trigger(name)
    scrollDriver.ts         # ScrollTrigger.update → gain/cutoff/playbackRate
    manifest.ts             # CC0 asset paths
  interaction/
    ScrollVelocity.ts       # rAF dy/dt smoothed → 0..1
    PointerParallax.ts      # lerp 0.08 pointer, touch fallback
    InteractionContext.tsx  # provider
  ui/
    StoryCopy.tsx           # reusable per-act copy
    CTAPanel.tsx            # Act 7 panel
    BootOverlay.tsx         # "Tap to begin" gesture gate
    ScrollProgress.tsx      # thin cyan progress bar
    MuteToggle.tsx          # localStorage persist
    RouteTransition.tsx     # cinematic wipe between routes
  components/
    LandingOverlay.tsx      # kept; wrapped by InvocationScene
    SiteNav.tsx             # extended w/ mute + pilot chip
    Docs.tsx                # extended w/ welcome ribbon + back link
  shaders.ts                # kept as-is
  App.tsx                   # ~120L composer
  index.tsx                 # hash router + reduced-motion gate
```

### Master-timeline pattern
One `gsap.timeline()` + one `ScrollTrigger` pinned to a `scrollContainerRef` whose height = `acts.length × window.innerHeight × actDurationFactor`. Each scene module exports `register(tl, label, ctx)` adding labelled tweens. Frame-by-frame logic (SOS Morse rhythm, mesh chain advance) lives in scene `update(dt, t, scrollProgress)` called by Engine rAF loop.

### Audio graph
```
AudioContext
└─ masterGain
   ├─ musicBus     (Gain → Convolver → masterGain)
   ├─ ambienceBus  (Gain → Convolver → masterGain)
   └─ sfxBus       (Gain → Convolver → masterGain)
```
Assets under `site3d/public/audio/`:
`harbor_dawn.ogg`, `engine_diesel.ogg`, `wind_ocean.ogg`, `rain_on_deck.ogg`, `radio_static_burst.wav`, `thunder_rumble.wav`, `pad_cmaj7.ogg`, `pad_resolve.ogg`. Attribution in `public/audio/LICENSES.md`. ECG beep + hop ping synthesized via `OscillatorNode`. Music detune via `playbackRate.linearRampToValueAtTime`. Storm muffle via biquad lowpass on musicBus.

### Docs bridge
Keep `#/docs` as separate route. Act 7 link → `RouteTransition.tsx` captures framebuffer snapshot, wipes upward while fading `#020205`, then sets `window.location.hash = '#/docs'`. Docs side: cyan ribbon "Welcome from the story" + "← Back to the story" top-left + floating "↶ Story" chip bottom-left. Reverse wipe on return.

### CTAs (Act 7)
`CTAPanel.tsx`, JetBrains Mono uppercase 12px:
1. **Run a pilot** — cyan `#00ffff` — `mailto:hello@example.com?subject=Pilot%20request` (TODO)
2. **See the code** — violet `#D54DFF` — `https://github.com/USER/REPO` (TODO)
3. **Stay in the loop** — off-white `#f5f0e8` — newsletter TODO

Plus smaller "Read the technical docs →" → `RouteTransition`. Buttons render over 30%-opacity harbor; parallax stays active behind. Footer band below: email, GitHub icon, license, "Built by …". `SiteNav.tsx` adds magenta "Pilot →" chip (Story route only).

### Reduced-motion fallback
`matchMedia('(prefers-reduced-motion: reduce)').matches` → skip master timeline + Engine. Render vertical stack of 7 static cards (title, single-line copy, still poster). Audio off. Mute toggle hidden. Docs link at bottom.

## Cleanup (Phase 1)

Delete:
- `site3d/components/Hero.tsx`
- `site3d/components/InputArea.tsx`
- `site3d/components/LivePreview.tsx`
- `site3d/components/CreationHistory.tsx`
- `site3d/services/firebase.ts`
- `site3d/services/gemini.ts`
- `site3d/services/` directory if empty
- `site3d/.firebaserc` and `site3d/firebase.json` if present

Edit:
- `site3d/package.json` — remove `@google/genai`, `firebase` deps; add `tailwindcss`, `postcss`, `autoprefixer` devDeps.
- `site3d/index.html` — remove `@google/genai`/`firebase` importmap entries; remove `<script src="https://cdn.tailwindcss.com">`; remove Inter font import (Rajdhani + JetBrains Mono only).
- `site3d/vite.config.ts` — remove `loadEnv` + `process.env.API_KEY`/`GEMINI_API_KEY` defines.
- `site3d/index.tsx` — remove `import './services/firebase';`.
- Add `site3d/postcss.config.js` + `site3d/tailwind.config.js`.

Verify: `npx tsc --noEmit` clean.

## Phases

### Phase 1 — Cleanup + modularization (no visual change)
**Files touched**: deletes per §Cleanup; new `engine/utils/*` extracted from `App.tsx`; `package.json`, `index.html`, `vite.config.ts`, `index.tsx`, `index.css`, new `postcss.config.js`, `tailwind.config.js`.
**Acceptance**:
- `npm run build` succeeds.
- `npm run dev` renders pixel-identical to current.
- `npx tsc --noEmit` zero errors.
- Bundle gz drops measurably (firebase + genai removed).

### Phase 2 — Narrative restructure
**Files touched**: rewrite of `App.tsx` (~120L); new `engine/Engine.tsx`, `engine/CameraRig.ts`, `engine/EngineContext.ts`, `engine/Loader.ts`; new `scenes/SceneRegistry.ts` + all 7 scenes + `ActScene.tsx`; new `ui/StoryCopy.tsx`, `CTAPanel.tsx`, `BootOverlay.tsx`, `ScrollProgress.tsx`; new `engine/utils/createSignalArcs.ts`, `createRain.ts`, `createHarborLights.ts`; amber accent constant.
**Acceptance**:
- Full 7-act scroll on desktop 1440×900 and mobile 375×667.
- No console errors.
- ScrollTrigger labels at every act boundary (DevTools markers).
- No `THREE.Material` leak warnings.

### Phase 3 — Audio + interaction
**Files touched**: new `audio/*` directory; new `interaction/*`; new `public/audio/*` + `LICENSES.md`; new `ui/MuteToggle.tsx`; update `SiteNav.tsx`; update `BootOverlay.tsx` (tap gate); wire `InteractionContext` into scenes.
**Acceptance**:
- Audio starts only after user gesture.
- Layer fades + filter sweeps correct across acts.
- Mute persists across reload.
- Mobile ≥45fps on iPhone 12-class device.
- Rapid scroll does not glitch audio (no clicks/pops).

### Phase 4 — Docs bridge + a11y + polish
**Files touched**: new `ui/RouteTransition.tsx`; update `index.tsx`, `SiteNav.tsx`, `Docs.tsx` (welcome ribbon + back link + floating chip + TOC anchors); reduced-motion fallback in `App.tsx`/`index.tsx`; meta tags in `index.html`.
**Acceptance**:
- Wipe transitions ≥30fps both directions.
- Deep-link anchors land correctly (`#/docs#hardware` etc.).
- Lighthouse mobile perf ≥80, accessibility ≥95.
- CLS <0.1.
- Reduced-motion path verified in DevTools (Rendering tab → emulate `prefers-reduced-motion: reduce` → reload `#/` → see 7 static cards).

## Verification (cross-phase)

- `npx tsc --noEmit` and `npm run build` per phase.
- DevTools console clean across full scroll (desktop + mobile).
- Performance trace ≥45fps mid-tier mobile across every act.
- Memory: navigate `#/ ↔ #/docs` five times, no Three.js leak (DevTools Memory tab).
- Browser back returns to correct story scroll position (`history.scrollRestoration = 'manual'` + `sessionStorage` scrollY).
- Bundle gz ≤350 KB (excluding audio). Audio compressed ≤2 MB; Acts 0–2 preloaded, Acts 3+ lazy.

## Palette reference
- Magenta `#D54DFF` — headings, post-relay boat color
- Cyan `#00ffff` — signals, mesh boats, ScrollProgress
- Electric blue `#4488ff` / `#00ccff` — particle palette, ocean tints
- Deep blue `#005599` / ultramarine `#031a2c` — ocean depth
- Red `#ff0000` — boat in distress, SOS pulse
- **Amber `#FFB347` (NEW)** — harbor lamps, family windows, dawn shift
- Dark bg `#020205` (page), `#111116` (scene/fog), storm `#050810`
- Off-white `#f5f0e8` (CTA), white `#ffffff` (body text)

## Typography
- Display: **Rajdhani** (300–700)
- Mono: **JetBrains Mono**
- Drop Inter (currently loaded but unused per project standard).
