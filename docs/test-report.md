# Test Report — Bug-fix round (OSRM/Nominatim CORS + insecure-origin geolocation)

## สรุป
Total: 10 | Pass: 9 | Fail: 0 | Gap flagged (not a fail, see below): 1

## Bug 1 — routing/directions CORS fix (`if (!kIsWeb)` on `User-Agent`)

- [x] **Code change correct & complete in all 3 files** — PASS
  - `lib/features/geo/data/osrm_routing.dart:80` — `headers: {if (!kIsWeb) 'User-Agent': _cfg.userAgent}`
  - `lib/features/geo/data/osrm_road_snap.dart:76` — same pattern
  - `lib/features/geo/data/nominatim_geocoding.dart:127-128` — `User-Agent` guarded, `'Accept-Language': 'th'` unconditional (correct: CORS-safelisted header, not part of this bug)
  - Grep for `User-Agent|userAgent` across `lib/features/geo/` found no other unguarded call site — the 3 files are the only places setting this header.
  - `kIsWeb` is correctly imported (`package:flutter/foundation.dart show kIsWeb`) in all 3 files.

- [x] **Native behavior unchanged** — PASS
  - `!kIsWeb` evaluates `true` on native builds/tests, so `User-Agent` is still sent every time on Android/iOS/desktop — confirmed by reading the guard logic and by the existing test `"NominatimGeocoding sends UA + Thai params..."` still passing (runs on the non-web test VM, i.e. `kIsWeb == false`).

- [x] **Geo test suite, no regressions** — PASS
  - `flutter test test/features/geo/osrm_road_snap_test.dart test/features/geo/services_test.dart` → **22/22 passed**, matches the previously-reported count.

- [x] **Independent assessment: is `if (!kIsWeb)` sufficient, any other header with the same CORS problem?** — PASS (sufficient)
  - Inspected the full header maps sent by all 3 fetch call sites (`osrm_routing.dart:80`, `osrm_road_snap.dart:76`, `nominatim_geocoding.dart:126-128`). Only two headers are ever sent: `User-Agent` (now guarded) and `Accept-Language: th` (CORS-safelisted per Fetch spec — browsers are permitted to set this without triggering a preflight, so it is not a candidate for the same bug). No other custom headers exist in these 3 files. Conclusion: the fix closes the only header that could trigger the CORS preflight failure described in dev-notes.

## Bug 2 — geolocation on insecure web origin

- [x] **`_isInsecureWebOrigin` logic correctness** — PASS
  - Verified with a standalone Dart script that `Uri.parse(...).host` is lowercase-normalized by the Dart `Uri` class itself (e.g. `http://LOCALHOST:8080/foo` → host `localhost`), so the case-sensitivity concern raised in scope is **not an actual bug** — Dart's own URI parsing handles it, not app logic.
  - Verified `Uri.host` never includes the port (confirmed `http://127.0.0.1:8080/foo` → host `127.0.0.1`), so the localhost-set comparison is unaffected by port — not a bug.
  - Verified `Uri.parse('http://[::1]:8080/...').host` → `::1` (brackets stripped by Dart), so the `'[::1]'` entry in `localHosts` (`geolocator_location_service.dart:49`) is dead/unreachable code — harmless, but worth a note for cleanup (not a functional bug).
  - Logic walk-through confirms: `https://` + any host → allowed (correct, matches browser secure-context spec which treats any HTTPS origin as secure regardless of host); `http://localhost`, `http://127.0.0.1`, `http://[::1]` → allowed; `http://172.20.10.7` (the reported LAN IP case) → correctly blocked (`scheme != 'https'` and host not in `localHosts`).

- [ ] **First-tap-ever gap (programmer's own flagged incomplete path)** — CONFIRMED REAL, flagged as a gap (not blocking sign-off, but should not be silently accepted as "done")
  - Traced the flow in `lib/features/geo/presentation/current_location.dart` `obtainCurrentLocation()`: on a true first tap, `loc.permission()` returns `denied` → shows consent dialog → calls `loc.request()` → on web this maps through `geolocator_web`'s `requestPermission()`, which (per dev-notes' own investigation) catches all exceptions on an insecure origin and always returns `LocationPermission.deniedForever` → mapped state is `deniedForever`, which is `!= granted`, so `current_location.dart:43-45` shows the generic `T.locOpenSettings` message and **returns before ever calling `currentPosition()`**, where the new `_isInsecureWebOrigin` check lives.
  - **Severity assessment: Medium, not Low.** The original bug report that triggered this whole fix explicitly was a user who said "I tapped Allow already" — i.e. a repeat-permission case — so the fix *does* correctly cover the reported repro. But the task framing in this round correctly points out that first-time users are arguably the more common real-world case (anyone testing via LAN IP for the first time, QA on a fresh browser profile, demo on a new device). For all of those, the fix's new, more actionable Thai message ("ต้องเปิดผ่าน HTTPS หรือ localhost...") never surfaces — they still get the generic "open settings" message, which is misleading on web (there is no OS settings app to open; the real fix is to use HTTPS/localhost). This undermines roughly half the value of the fix for its likely audience. Recommend a follow-up: in `current_location.dart`, when `state != granted` and `kIsWeb` and the origin is insecure, show the HTTPS-specific message instead of `T.locOpenSettings` (or have `request()` short-circuit the same way `currentPosition()` does).

- [x] **`geolocator_location_service_test.dart`** — PASS, 10/10 passed, no regressions.
- [x] **`contract_and_safety_test.dart`** — PASS, **13/13** passed, no regressions. Note: dev-notes.md claims "14/14" — actual count is 13 tests in this file (minor documentation discrepancy, not a functional issue; all 13 pass).
- [x] **Native (Android/iOS) geolocation behavior unchanged** — PASS
  - `_isInsecureWebOrigin` returns `false` immediately via the `if (!kIsWeb) return false;` guard — on native `kIsWeb` is a compile-time `false` constant, so this branch is dead code on native builds and `currentPosition()` proceeds straight to the existing `Geolocator.getCurrentPosition()` call, unchanged. The new `on PermissionDeniedException` catch clause only changes the *mapped failure code* (`locationDenied` instead of `locationUnavailable`) for a permission-denied exception — this is a message-only change, not a behavior/flow change, and is arguably a strict improvement (more accurate code) rather than a regression risk. Confirmed via `geolocator_location_service_test.dart` passing unchanged (tests run with `kIsWeb == false`).

## flutter analyze (whole project)
- **16 issues, all `info` level, all pre-existing and unrelated to either bug fix** (deprecated `RadioGroup`/`groupValue` usage in `theme_settings_screen.dart`, `gender_settings_screen.dart`; `prefer_const_constructors` in `tokens.dart`, `me_tab.dart`). Zero issues in any of the files touched by Bug 1 or Bug 2 (`lib/features/geo/**`, `lib/core/error/**`). No errors, no warnings.

## Coverage ที่ยังขาด
- No automated test currently exercises the "first tap, insecure web origin" path end-to-end (the confirmed gap above) — would require a widget-level test of `obtainCurrentLocation()` with a fake `LocationService` returning `deniedForever` plus `kIsWeb` simulated true, which the current unit-test setup for `geolocator_location_service_test.dart` doesn't cover (it tests the service, not the presentation-layer flow).
