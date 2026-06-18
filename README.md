# hearth-mobile

Flutter companion app for Hearth. Handles the things WhatsApp can't: background geofencing,
quick-capture UI, native chat, wiki browsing, and a dashboard view.

All backend communication goes to the Hearth Express server on Fly.io — fully JWT-protected,
no unauthenticated routes.

## Status

Scaffold complete — core screens, services, and Android config are in place. Not yet built
against a real device (requires Windows Developer Mode for symlink support). Background
service wiring and Bluetooth/NFC listeners are stubbed but not yet active.

## CI

Every push to `master` builds a release APK via GitHub Actions and publishes it as a
tagged release (`build-<sha>`). Download the latest APK from the
[Releases](https://github.com/raedur/hearth-mobile/releases) page.

## What this app does

1. **Auth** — WhatsApp-as-IdP: the app opens WhatsApp with a one-time code, the bot issues
   a JWT via deep link. Silent refresh via opaque rotation token. Users never re-authenticate
   manually as long as the app is opened occasionally.

2. **Wiki** — browse and search the family wiki. Read-only rendered markdown view.

3. **Signals** — configure named GPS geofences and WiFi networks. App posts silently when
   signals fire, triggering Hearth tasks automatically.

## Tech

- Flutter 3.41+ / Dart 3.11+
- Android-first (min SDK 23), iOS later
- Java 21 / Gradle 8.14 / Kotlin 2.2
- Auth: WhatsApp-as-IdP → JWT (1hr) + opaque refresh token (rotating, no expiry)
- All API calls hit the Hearth Express server (JWT-protected)

## Building locally

```
flutter pub get
flutter build apk --release
```

The APK is output to `build/app/outputs/flutter-apk/app-release.apk`.

For development with hot reload:

```
flutter run
```

See `architecture.md` for design details, auth flow, signal design, and API surface.
