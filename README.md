# hearth-mobile

Flutter companion app for Hearth. Handles the things WhatsApp can't: background geofencing,
quick-capture UI, native chat, wiki browsing, and a dashboard view.

All backend communication goes to the Hearth Express server on Fly.io — fully JWT-protected,
no unauthenticated routes.

## Status

Planned. Not yet scaffolded. See `architecture.md` for the intended design.

## What this app does

1. **Auth** — WhatsApp-as-IdP: the app opens WhatsApp with a one-time code, the bot issues
   a JWT via deep link. Silent refresh every 7 days. Users never re-authenticate manually
   as long as the app is used regularly.

2. **Chat** — native chat UI backed by the Hearth bot. Equivalent to messaging the bot on
   WhatsApp, but with a purpose-built interface.

3. **Wiki** — browse and search the family wiki. Read-only view of the markdown files
   with rendered output.

4. **Dashboard** — native view of tasks, reminders, and shopping list. Checkable items,
   upcoming events, today's briefing.

5. **Quick capture** — fast-add a note, photo, or voice memo. Sends to the Hearth server
   as a message from the authenticated member. Also registered as an Android share target.

6. **Geofencing / signals** — configure named locations, WiFi networks, Bluetooth devices,
   and NFC tags. App posts silently when signals fire, triggering Hearth tasks automatically.

## Tech

- Flutter (Dart)
- Target: Android first, iOS later
- Auth: WhatsApp-as-IdP → JWT access token + opaque refresh token
- All API calls go to the Hearth Express server (JWT-protected)

## Setup (when ready to build)

```
flutter create . --org au.id.craig --project-name hearth_app
flutter pub get
```

See `architecture.md` for dependency choices and implementation notes.
