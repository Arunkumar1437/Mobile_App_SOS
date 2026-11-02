# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

AK SOS (originally "Suraksha SOS"): a Flutter app (Android/iOS, built for India) with a one-tap SOS that opens the SMS app pre-filled with the user's GPS location for 112 plus saved contacts, and looks up nearby police, railway, airport, hospital, fire, bus and pharmacy places from OpenStreetMap. No API keys or backend. `README.md` covers the user-facing feature list and rationale.

## Commands

The repo is a partial Flutter project: only `lib/`, `pubspec.yaml`, `analysis_options.yaml`, `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist` are checked in. There is no `android/build.gradle`, `ios/Runner.xcodeproj` or `test/` directory until the platform files are generated. Do this once on a fresh checkout (existing manifest and plist are preserved):

```bash
flutter create --org com.example --project-name suraksha_sos --platforms=android,ios .
flutter pub get
```

Day to day:

`flutter create` also writes a template `test/widget_test.dart` that instantiates `MyApp`. This app's root widget is `SurakshaApp`, so that file fails `flutter analyze` and `flutter test` until it is rewritten or deleted.

```bash
flutter run                          # run on a connected device or emulator
flutter analyze                      # lints (flutter_lints, no custom rules)
flutter test                         # no tests exist yet
flutter test test/foo_test.dart      # a single test file
flutter build apk --release          # -> build/app/outputs/flutter-apk/app-release.apk
```

Flutter was not on `PATH` in the Windows shells used so far; check `flutter --version` before assuming it works. Requires Flutter 3.24+ and Dart `>=3.4.0 <4.0.0`.

When trying the SOS flow, turn off "Include 112 in SOS SMS" on the Contacts tab and add your own number, so test messages do not go to 112.

## Architecture

State management is plain `StatefulWidget` + `setState`. There is no provider, bloc or router. All logic lives in static-method service classes under `lib/services/`, and screens call them directly.

- `main.dart` builds a Material 3 `MaterialApp` (red seed colour, light and dark themes) whose home is `HomeShell`.
- `screens/home_shell.dart` is a `NavigationBar` over an `IndexedStack` of four screens (SOS, Nearby, Contacts, Helplines). The `IndexedStack` keeps every tab alive, so each screen's `initState` runs once at app start. SOS and Nearby both request location and hit the network at launch. `SosScreen` takes an `onOpenContacts` callback that switches `HomeShell` to tab index 2, so reordering tabs means updating that index.
- `models/place.dart` defines `PlaceCategory`, an enum that carries each category's label, icon and colour, plus the shared `searchRadiusMeters` constant (10 km, used by every category), the `Place` model and `formatDistance`.

### Cross-file flows to know about

- **SOS flow** (`screens/sos_screen.dart`): idle → countdown (5s, tap again to send immediately, long-press to skip the countdown) → working → done or failed. `_triggerSos` gets a fresh GPS fix, falls back to `_position` and then `LocationService.lastPosition` when that fails, queries the nearest police with an 8-second timeout, and then calls `SosService.openSms`. Every failure along the way is swallowed so the SMS still opens. Keep that "never block the SOS" property when editing.
- **SMS hand-off** (`services/sos_service.dart`): by default the app opens the SMS app pre-filled and the user taps Send. The opt-in "Send SOS SMS automatically" setting (`StorageService.loadAutoSend`, off by default, Android only) instead texts straight from the phone: `SosService.sendSms` calls a `MethodChannel` (`com.example.suraksha_sos/sms`) implemented in `android/app/src/main/kotlin/com/example/suraksha_sos/MainActivity.kt`, which uses `SmsManager`, asks for `SEND_SMS` at runtime, and reports per-number success from the sent-intent callbacks (30 s cap). `SosScreen._deliver` tries it first and falls back to `openSms` for anything that fails or when the permission is missing, so the SOS still goes out. `SEND_SMS` is restricted by Google Play (see README), and the channel does not exist on iOS. `openSms` builds a different URI per platform (iOS `sms://open?addresses=...` or `sms:N&body=`; Android `sms:a;b?body=`) and falls back to `112` when there are no recipients. `SosService` also holds `call`, `directions` and `cleanPhone`, which every screen uses.
- **Settings sync** (`services/storage_service.dart`): contacts, the SOS message and the "include 112" flag are persisted with `shared_preferences`. Every `save*` bumps the static `StorageService.changes` `ValueNotifier`. `SosScreen` listens to it and reloads, which is how edits on the Contacts tab reach the SOS tab without sharing state. New persisted settings should bump `changes` too.
- **Location** (`services/location_service.dart`): `quick()` returns the session's last fix or the phone's last known one without waiting for GPS; `NearbyScreen` starts from it and corrects itself in `_refine` once a real fix arrives. `getCurrent()` (concurrent callers share one in-flight fix, since SOS and Nearby both ask at launch) checks that GPS is on, then permission, then takes a 15-second high-accuracy fix, falling back to `getLastKnownPosition` and the cached static `lastPosition` on timeout. It throws `LocationException` with a `LocationFix` hint (`turnOnGps` or `openAppSettings`) that the UI maps to an "Open settings" button via `applyFix`.
- **Nearby places** (`services/places_service.dart`): it POSTs an Overpass QL query by racing four public mirrors (`overpass.openstreetmap.fr`, `overpass-api.de`, `overpass.kumi.systems`, `overpass.private.coffee`): one request starts every 2 s (or at once when the previous one fails) over a shared keep-alive `http.Client`, and the first good answer wins. Racing is deliberate: in testing `overpass-api.de` took 31 s or timed out and `kumi` never answered, while the `.fr` mirror took about 0.9 s, and trying mirrors one after another left the Nearby list empty. Results are cached in memory per category and location rounded to 3 decimals for 10 minutes. Each successful search is also saved to `shared_preferences` (`nearby_<category>`, one slot per category). `lastKnown()` returns that slot with distances recomputed if it was fetched within 500 m and 7 days, so `NearbyScreen` paints a list instantly and refreshes behind it. A fresh query cannot beat about 0.9 s (0.35 s connect and TLS plus 0.5 s server work), so that instant paint is what makes repeat opens feel immediate. Every category searches the same `searchRadiusMeters` (10 km) with no widening. The query has no `out` cap, because Overpass returns arbitrary elements rather than the nearest, so a cap could drop the closest places. `_filter` holds the per-category OSM tag selectors. `_parse` dedupes by name and rounded coordinates, sorts by distance, and keeps 100 places. Phone, address and the `extra` field (IATA code, station code, "24x7 emergency", opening hours) are best-effort extractions from OSM tags. To add a place category, add a `PlaceCategory` enum entry with its radius, then a `_filter` case and an `_extra` case. `_filter` has no `default`, so Dart's exhaustive enum switch makes a missing case a compile error. `_extra` has a `default` and will silently fall through to the `operator` tag.

### Platform config

Permissions and URL-launching rules live in the checked-in `AndroidManifest.xml` (location, internet and `SEND_SMS` permissions, plus `<queries>` entries so `url_launcher` can see the sms, tel and https handlers on Android 11+) and `Info.plist` (`NSLocationWhenInUseUsageDescription`, `LSApplicationQueriesSchemes` for sms, tel and https). New `url_launcher` schemes or new permissions need an edit in both files. `flutter create` must not overwrite them (the README documents that it doesn't).
