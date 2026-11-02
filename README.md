# AK SOS (Flutter)

One-tap SOS with your live GPS location, plus nearby police stations, railway
stations, airports, hospitals, fire stations, bus stands and pharmacies.
Built for India. No API keys or paid services needed.

## Features

| Tab | What it does |
|---|---|
| **SOS** | Big SOS button: tap for a 5-second countdown (cancel anytime) or hold to send instantly. Gets your GPS location, finds the nearest police station, and opens your SMS app pre-filled for **112 + your emergency contacts** with a Google Maps link, accuracy, nearest police station and time. One-tap calls to 112, 108 and the nearest police station. |
| **Nearby** | Police, Railway, Airport, Hospital, Fire Station, Bus Stand, Pharmacy — within 10 km, sorted by distance, with address, phone, station code / IATA code, **Call** and **Directions** (Google Maps). List or map view. |
| **Contacts** | Add/remove emergency contacts, edit your SOS message, turn 112 on/off (use off while testing), optional automatic SMS sending (Android). |
| **Helplines** | One-tap Indian helplines: 112, 100, 101, 108, 1091, 181, 1098, 139 (Rail Madad), 1930 (cyber crime), 1033 (highway) and more. |

## Run it

1. Install Flutter 3.24 or newer: https://docs.flutter.dev/get-started/install
2. In this folder, generate the Android/iOS platform files (your `lib/`,
   `AndroidManifest.xml` and `Info.plist` are kept because they already exist):

   ```bash
   flutter create --org com.example --project-name suraksha_sos --platforms=android,ios .
   flutter pub get
   ```
3. Connect an Android phone (USB debugging on) and run:

   ```bash
   flutter run
   ```
4. Build an installable APK:

   ```bash
   flutter build apk --release
   # -> build/app/outputs/flutter-apk/app-release.apk
   ```

Change `com.example` to your own package id before publishing.

## ⚠️ Testing safely

Turn **"Include 112 in SOS SMS"** off on the Contacts tab and add your own
number as a contact while testing. Do not send test messages to 112.

## How the SOS works (and why)

- **Police stations in India do not take SMS/app messages directly.** The
  official channel is **112** (ERSS), which accepts calls and SMS. The app
  sends to 112 and your contacts, and lets you call the nearest police
  station when OpenStreetMap lists its phone number (usually a landline).
- **By default the app opens the SMS app pre-filled; you tap Send.** On Android
  you can switch on **Send SOS SMS automatically** (Contacts tab): the app then
  texts 112 and your contacts straight from the phone, with no tap. It asks for
  Android's `SEND_SMS` permission when you turn the switch on (off by default,
  so a test press never texts 112 by surprise). Any number that cannot be sent
  (no signal, permission refused) falls back to the pre-filled SMS app. Google
  Play only allows `SEND_SMS` for default SMS apps or approved exceptions, so
  use auto-send for APKs you install directly, or get approval before
  publishing. iOS never allows silent SMS, so it always opens the SMS app.
- If GPS fails, the SOS still goes out with the last known location, or with
  "location unavailable".

## Data sources

- Nearby places: **OpenStreetMap** via the free Overpass API
  (`lib/services/places_service.dart`). Coverage is good in cities like
  Chennai but some police stations lack phone numbers or names. Respect the
  Overpass fair-use policy; for heavy traffic, host your own Overpass server
  or switch to Google Places / Mappls (MapmyIndia) APIs.
- Map tiles: `tile.openstreetmap.org`. For a published app with many users,
  use a tile provider (MapTiler, Stadia, Mappls) — OSM's own tiles are for
  light use only.

## Project layout

```
lib/
  main.dart                    app + theme
  models/place.dart            place categories and model
  services/location_service.dart   GPS + permission handling
  services/places_service.dart     OpenStreetMap / Overpass lookup
  services/sos_service.dart        SOS text, SMS, calls, directions
  services/storage_service.dart    saved contacts + settings
  screens/                     SOS, Nearby, Contacts, Helplines
android/app/src/main/AndroidManifest.xml   permissions + intent queries
ios/Runner/Info.plist                      location text + URL schemes
```

## Ideas for next versions

- Shake / power-button trigger, and a home-screen widget
- Live location sharing every few minutes until "I'm safe"
- Auto-send SMS (outside Play Store) and auto-call 112 after SOS
- Tamil / Hindi translations
- Record audio during SOS
