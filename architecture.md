# hearth-mobile — Architecture

## Guiding constraints

- No new backend infrastructure — every API call hits the existing Hearth Express server
- Android-first; iOS support comes later without a rewrite (Flutter handles this)
- Auth is WhatsApp-as-IdP — no passwords, no OAuth server, no third-party auth provider
- The app is a **context bridge** — it turns physical-world signals into API calls that
  Hearth processes as plain-text messages. The brain doesn't need to know the signal source.

---

## Auth model

### Overview

WhatsApp is the identity provider. The user's verified phone number — already linked to a
member name via the Hearth pairing flow — is the root of trust.

```
Access token:   JWT, signed by hearth-core, 1-hour expiry
Refresh token:  Opaque random ID, stored server-side, no expiry
```

Tokens are stored in platform secure storage (iOS Keychain, Android Keystore) via
`flutter_secure_storage`. Never in `shared_preferences`.

### First-time login

1. App generates a random 6-character nonce (e.g. `X7KP2M`), stores it locally with a
   5-minute TTL.
2. App opens WhatsApp with pre-drafted message to the Hearth bot number:
   `HEARTH-AUTH:X7KP2M`
3. User sends it. WhatsApp cryptographically guarantees the sender identity.
4. hearth-core receives it, verifies sender JID is a registered member, and:
   - Signs a JWT: `{ sub: jid, name: "Ryan", nonce: "X7KP2M", exp: +1hr }`
   - Generates an opaque refresh token, stores it in `refresh_tokens.json` on the Fly volume
   - Sends back via WhatsApp: `hearth://auth?token=<JWT>&refresh=<refresh_token>`
5. User taps the deep link. App opens, captures both tokens.
6. App verifies: JWT signature valid, nonce matches what it generated, not expired.
7. Both tokens stored in secure storage. Auth complete.

The nonce prevents a confused-deputy attack: if someone tricks Ryan into sending
`HEARTH-AUTH:attacker_nonce`, the deep link goes to Ryan's WhatsApp — but Ryan's app
rejects it because the nonce doesn't match its pending session.

### Token refresh (silent, every 7 days)

```
POST /api/refresh
{ "refreshToken": "abc..." }

→ server looks up token in refresh_tokens.json
→ valid? issue new JWT (1hr) + new refresh token, invalidate old
→ app stores new pair
```

Refresh token rotation: each use issues a new refresh token and invalidates the old one.
If a stolen refresh token is used, the legitimate device's next refresh fails — the user
gets a re-auth prompt, alerting them to the compromise.

As long as the app is used at least once every 7 days the user never sees a login prompt.
Opening the app after months of disuse: the refresh token is still valid (time passing
doesn't expire it) — silent refresh succeeds, user is in.

### Revocation

| Situation | Action |
|---|---|
| Remove member from `WHATSAPP_MEMBERS` | Their JID rejected at next refresh (within 7 days) |
| Device lost/stolen | Delete their record from `refresh_tokens.json` via `fly ssh console` |
| Immediate full revocation | Roll `JWT_SECRET` env var — all tokens invalid instantly, everyone re-authenticates via WhatsApp |

### Re-authentication

Only required when:
- Refresh token was explicitly revoked
- `JWT_SECRET` was rolled
- App was unused for over 30 days AND the 1-hour access token has expired (edge case —
  the refresh token is still valid so this resolves silently on next open)

Re-auth flow is identical to first-time login.

---

## Phone signals

The app can bridge a range of phone signals into Hearth API calls. All of them produce
plain-text messages — "Ryan is at the shops", "Ryan is home", "Ryan is driving" — which the
brain processes using the same task-matching logic as any other message.

### GPS geofencing
Named locations (shops, school, work). Fires on arrival. See geofencing design section.
Most useful for locations away from home.

### WiFi network detection
Connect to a known SSID → fire a trigger. Often *more* reliable than GPS for indoor
locations and costs nothing in battery. Complementary to GPS: use GPS for out-of-home
locations, WiFi for home/work/school where the network is known.

Examples:
- Connect to home WiFi → "Ryan is home"
- Connect to school WiFi → "Ryan is at school pickup"
- Connect to work WiFi → "Ryan is at work"

Flutter package: `network_info_plus` for SSID detection. Background monitoring via
`flutter_background_service`.

### Bluetooth device detection
Connect to a known Bluetooth device → fire a trigger. Most useful for the car.

Examples:
- Connect to car Bluetooth → "Ryan is in the car"
- Disconnect from car Bluetooth at a known time → "Ryan has arrived somewhere"

Flutter package: `flutter_bluetooth_serial` or `blue_thermal_printer` (evaluate at build
time — Bluetooth package quality varies).

### NFC tags
Cheap physical tags (~$0.50 each) stuck at specific spots around the house. Tap to trigger.
More precise than any sensor — GPS can't tell you someone opened the medicine cabinet.

Suggested placements and their triggers:
- **Front door (inside)** → "Ryan is leaving home"
- **Fridge** → "Ryan checked the fridge" — Hearth responds with shopping list items to
  pick up or anything that needs restocking
- **Medicine cabinet** → triggers any outstanding medication reminders for the family
- **Kids' school bag hook** → "Phoebe's bag is packed" / check for any school items needed
- **Car dashboard** → departure log, or trigger active tasks relevant to driving

Flutter package: `nfc_manager`. Android supports NFC natively; iOS requires iPhone 7+
with a specific entitlement (later concern).

### Activity recognition
Android's built-in Activity Recognition API detects: walking, running, cycling, driving,
still. Low battery cost, no permissions beyond `ACTIVITY_RECOGNITION`.

Most useful signal: **driving detected** → suppress non-urgent nudges for the duration.
Also useful as a fallback arrival signal when GPS/WiFi haven't fired yet.

Flutter package: `activity_recognition_flutter`.

### Alarm dismissed
When the morning alarm is swiped away, the app fires the daily briefing immediately rather
than waiting for the fixed 07:00 scheduler.

Implementation: listen for `Intent.ACTION_ALARM_CHANGED` on Android, or monitor the
system alarm via `android_alarm_manager_plus`.

### Share sheet
Register Hearth as a share target. From any Android app, Share → Hearth sends the content
to the API. This makes capture frictionless from anywhere on the phone.

What families would share:
- **Photos** → filed to the wiki (product shots, receipts, kids' artwork, moments)
- **Webpages** → gift ideas, products to research, articles to save
- **Contacts** → saved to `misc.md` or the relevant person's file
- **Text/screenshots** → anything worth remembering

Flutter package: `receive_sharing_intent`.

---

## Quick tiles and widgets

### Quick tiles
Custom tiles in the Android notification shade — accessible without unlocking the phone.
One tap sends a specific message to the API.

Suggested tiles (user-configurable):
- "I'm at the shops"
- "School pickup done"
- "Kids are in bed"
- Custom (user-defined label + message)

Implementation: Android `TileService` via a platform channel in Flutter, or a native
Android module alongside the Flutter app.

### Home screen widgets
- **Shopping list widget** — shows current list, items checkable in place
- **Today summary widget** — shows today's key items from the morning briefing

Implementation: `home_widget` Flutter package for Android (and eventually iOS).

---

## Flutter dependencies (intended)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # HTTP
  http: ^1.2.0

  # Deep link handling — captures hearth://auth?token=...&refresh=... on app open
  app_links: ^6.0.0

  # Secure token storage — iOS Keychain, Android Keystore (NOT shared_preferences)
  flutter_secure_storage: ^9.0.0

  # Background service — keeps all background signal monitoring alive
  flutter_background_service: ^5.0.0

  # GPS geofencing
  geolocator: ^13.0.0

  # WiFi SSID detection
  network_info_plus: ^6.0.0

  # NFC
  nfc_manager: ^3.3.0

  # Activity recognition (driving, walking, still)
  activity_recognition_flutter: ^3.0.0

  # Share sheet (receive shared content from other apps)
  receive_sharing_intent: ^1.8.0

  # Home screen widgets
  home_widget: ^0.7.0

  # Local storage (geofence config, cached shopping list — non-sensitive only)
  shared_preferences: ^2.3.0

  # State management
  provider: ^6.1.0

  # Markdown rendering (wiki screen)
  flutter_markdown: ^0.7.0
```

---

## Screen structure

```
lib/
├── main.dart                   # App entry, MaterialApp, routes, auth gate
├── screens/
│   ├── login_screen.dart       # "Connect with WhatsApp" button → nonce → deep link
│   ├── chat_screen.dart        # Native chat UI — messages to/from the Hearth bot
│   ├── wiki_screen.dart        # Browse and search wiki markdown files
│   ├── dashboard_screen.dart   # Tasks, reminders, shopping list — native JSON view
│   ├── capture_screen.dart     # Quick note/photo/voice → POST /api/capture
│   └── settings_screen.dart   # Geofence config, WiFi/BT/NFC setup, signal toggles
├── services/
│   ├── api_service.dart        # All HTTP calls — injects Authorization: Bearer header
│   ├── auth_service.dart       # Nonce generation, deep link handling, token storage,
│   │                           #   silent refresh (called by api_service on 401)
│   ├── geofence_service.dart   # GPS geofence monitoring + API trigger
│   ├── wifi_service.dart       # Known SSID monitoring + API trigger
│   ├── bluetooth_service.dart  # Known device monitoring + API trigger
│   ├── nfc_service.dart        # NFC tag read handler + API trigger
│   ├── activity_service.dart   # Activity recognition — driving suppression etc.
│   └── share_service.dart      # Receives shared content, routes to /api/capture
└── models/
    ├── shopping_item.dart
    ├── task.dart
    └── wiki_file.dart
```

### Auth gate

`main.dart` wraps all screens in an auth gate: if no valid access token in secure storage,
show `login_screen.dart`. On deep link receipt (`hearth://auth?token=...&refresh=...`),
`auth_service.dart` validates and stores tokens, then navigates to the main shell.

`api_service.dart` handles 401 responses by attempting a silent refresh. If refresh
succeeds, it retries the original request transparently. If refresh fails (token revoked),
it clears stored tokens and routes to `login_screen.dart`.

---

## Geofencing design

### The goal
When a member arrives at a tagged location, the app silently POSTs to the Hearth API.
Hearth processes it as if the member sent "I'm at the shops" — the brain then fires any
matching `trigger:` tasks from `tasks/active.md`.

### How it works
1. Member configures named locations in-app (name + lat/lng, set by dropping a pin or
   using current location). Stored in `shared_preferences`.
2. `geofence_service.dart` registers a background task that wakes every N minutes and
   checks current position against stored geofences.
3. On entry detection: POST to `/api/capture` with JWT auth and body
   `{ "text": "Ryan is at [location name]" }`.
4. Hearth's brain processes this as a normal message and fires matching tasks.

### Platform notes
- **Android:** Background location requires `ACCESS_BACKGROUND_LOCATION` permission
  (Android 10+). The user will be prompted to allow "all the time" location access.
  `flutter_background_service` keeps the check alive as a foreground service with a
  persistent notification.
- **iOS (future):** Core Location significant-change monitoring is the right approach —
  less battery than continuous polling. `geolocator` handles this transparently.

### Battery considerations
Continuous GPS polling is expensive. The approach:
- Poll every 5 minutes (not continuous)
- Only activate geofence checks when the member is not at home (home = base location)
- Use `Geolocator.getLastKnownPosition()` where fresh position isn't needed

---

## API surface

All calls go to the Hearth Express server. Every route requires `Authorization: Bearer <access_token>`.

| Screen / service | Endpoint | Method | Notes |
|---|---|---|---|
| Auth refresh | `/api/refresh` | POST | Body: `{ refreshToken }` — returns new JWT + refresh token |
| Chat | `/api/chat` | POST | Body: `{ text }` — returns `{ reply }` |
| Wiki list | `/api/wiki` | GET | Returns list of wiki files with metadata |
| Wiki file | `/api/wiki/:path` | GET | Returns rendered markdown content |
| Dashboard | `/api/dashboard` | GET | Returns tasks, reminders, today summary as JSON |
| Shopping list | `/api/shopping` | GET | Parsed shopping list items |
| Check off item | `/api/shopping/:item` | DELETE | Removes item, commits to wiki |
| Quick capture | `/api/capture` | POST | Body: `{ text, media? }` — processed as a member message |
| Signal trigger | `/api/capture` | POST | Same endpoint — geofence/WiFi/NFC/BT signals |

---

## What this app deliberately does not do

- Push notifications — WhatsApp already handles nudges; duplicating this adds complexity
- Full wiki editor — the webchat handles this; a native wiki editor is a much bigger build
- Offline mode — Hearth requires a live connection anyway (LLM calls, git operations)
- User management — adding/removing members is an admin task done via env vars + `fly ssh`
