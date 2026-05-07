# App Instruction Document
## Private 2-Person Messenger — Flutter

---

## Overview

A private, personal messaging app built exclusively for 2 people. No social features, no accounts, no clutter. Just a clean private space to chat, share content from other apps, send photos, and collaborate on a shared whiteboard.

---

## Core Concept

- Strictly 2 users only — no group chats, no strangers
- All chat data stored locally on each phone (SQLite)
- Messages synced in real time via a lightweight WebSocket relay server
- The server acts as a dumb pipe — it relays messages but stores nothing
- No LLM or AI integration

---

## Features

### 1. Private Messenger
- Real-time text messaging between 2 devices
- Messages stored locally in SQLite/Drift on each phone
- Timestamps on every message
- Clean minimal chat UI
- Typing indicator
- Message delivered/read receipts (local only)

### 2. Reel & Content Sharing (Share Sheet Integration)
- App registers as a share target on Android/iOS
- Any content (Instagram reels, YouTube videos, TikToks, articles, links) can be shared directly into the app from any other app via the native share sheet
- Shared content appears as a rich card in the chat (thumbnail + link + title if available)
- Both users see the shared content inside their chat

### 3. Photo Sharing (Snap-style updates)
- Quick camera access inside the app
- Send photos directly in chat (food, shopping, daily life updates etc)
- Photos stored locally on both devices
- Full screen photo viewer on tap
- No disappearing, no timers — photos persist in chat history

### 4. Shared Realtime Whiteboard
- A shared canvas accessible to both users simultaneously
- Both can draw, write, sketch, or annotate in real time
- Drawing strokes synced via the same WebSocket relay as messages
- Accessible as a dedicated screen or widget within the app
- Clear/reset button to wipe the canvas (both sides clear simultaneously)
- Persistent between sessions (canvas state saved locally)

### 5. Custom Nicknames
- Each user can set a nickname for themselves and for the other person
- Nicknames appear throughout the app — chat bubbles, profile header, whiteboard attribution
- Stored locally in SQLite
- Change anytime from settings
- Nickname update synced to the other phone via WebSocket so both sides always see the latest names

### 6. Theme Packs
- A set of pre-built UI themes that change the entire look and feel of the app
- Both users can independently choose their own theme — themes are not synced
- Theme changes apply app-wide: chat bubbles, background, fonts, colors, whiteboard canvas background
- Suggested theme pack ideas:
  - **Default** — clean minimal dark
  - **Midnight** — deep black with neon accents
  - **Paper** — warm off-white, handwritten feel
  - **Forest** — muted greens and earthy tones
  - **Retro** — pixel-style, 8-bit color palette
  - **Pastel** — soft pinks and lilacs, light mode
- Theme stored locally in SharedPreferences
- Built using Flutter's `ThemeData` and a custom `ThemeProvider` with `Provider` or `Riverpod`

### 7. Live Location Sharing
- Both users can see each other's real-time location on a map inside the app
- Location sharing is opt-in — each user toggles it on/off independently
- When active, location updates sent periodically via WebSocket (every 15–30 seconds)
- Displayed on an in-app map (using `flutter_map` with OpenStreetMap tiles — fully free, no API key needed)
- Shows both users as pins/avatars on the same map
- Location data is never stored — only relayed live and held in memory
- Auto-stops sharing when app is backgrounded or user toggles off

### 8. Spotify Activity (Now Playing)
- Shows what the other person is currently listening to on Spotify — similar to Discord's activity status
- Displayed as a small card/banner in the chat header or a dedicated status area
- Shows: song name, artist, album art
- Implementation via **Spotify Web API** (free, requires each user to log in with their own Spotify account once)
- Polling-based: app checks Spotify's `/me/player/currently-playing` endpoint every 30 seconds
- If nothing is playing, status shows as empty/hidden
- Each user authenticates their own Spotify — app stores the OAuth token locally
- Now playing status broadcast to the other user via WebSocket
- WebSocket message type: `{ "type": "spotify_activity", "song": "...", "artist": "...", "albumArt": "..." }`

---

## Technical Stack

### Frontend
- **Framework:** Flutter (Dart)
- **Platform:** Android & iOS
- **Local Storage:** Drift (SQLite wrapper for Flutter) — stores messages, media references, whiteboard state
- **Real-time:** WebSocket client (`web_socket_channel` package)
- **Camera:** `image_picker` or `camera` package
- **Share target:** `receive_sharing_intent` package (handles incoming shares from other apps)
- **Whiteboard:** Flutter `CustomPainter` with canvas drawing + stroke sync via WebSocket
- **Media storage:** Local file system (app documents directory)
- **Theme:** `Provider` or `Riverpod` with Flutter `ThemeData`
- **Location:** `geolocator` package + `flutter_map` with OpenStreetMap (no API key needed)
- **Spotify:** Spotify Web API via OAuth2 (`spotify_sdk` or direct HTTP with `flutter_secure_storage` for tokens)

### Backend
- **Runtime:** Node.js
- **Protocol:** WebSocket (via `ws` package)
- **Role:** Dumb relay only — receives a message from one client, forwards to the other. Stores nothing.
- **Hosting:** Free tier — Railway, Render, or Fly.io
- **No database on server side**

---

## Architecture

```
Phone A                    Relay Server               Phone B
  |                            |                          |
  |--- send message ---------->|--- forward message ----->|
  |                            |                          |
  |<-- receive message --------|<-- send message ---------|
  |                            |                          |
  | (stores locally)           | (stores nothing)         | (stores locally)
```

---

## Data Storage (Local — Each Phone)

| Data | Storage |
|------|---------|
| Chat messages | SQLite via Drift |
| Shared links/reel cards | SQLite via Drift |
| Photos | Local file system, path stored in SQLite |
| Whiteboard canvas state | SQLite or local JSON file |
| Nicknames | SQLite via Drift |
| Selected theme | SharedPreferences |
| Spotify OAuth token | SharedPreferences (secure storage) |
| Live location | Memory only — never persisted |

---

## Pairing / Connection

- First-time setup: one user generates a pairing code or QR code
- Second user scans/enters it to link their app to the same relay channel
- Both phones connect to the same WebSocket room on the relay server
- Pairing is one-time — persists in local storage

---

## App Screens

1. **Chat Screen** — main messaging UI, shows text + shared content cards + photos + Spotify status banner
2. **Camera / Photo Picker** — quick access to send a photo
3. **Whiteboard Screen** — shared drawing canvas
4. **Content Preview** — full screen view for shared reels/links and photos
5. **Map Screen** — live location of both users on OpenStreetMap
6. **Settings Screen** — nicknames, theme picker, Spotify login, pairing, connection status

---

## WebSocket Message Types

All messages are JSON objects sent over WebSocket:

```json
{ "type": "text", "content": "Hey!", "timestamp": 1234567890 }
{ "type": "photo", "filename": "img_001.jpg", "timestamp": 1234567890 }
{ "type": "share", "url": "https://...", "title": "Reel title", "thumbnail": "https://...", "timestamp": 1234567890 }
{ "type": "whiteboard_stroke", "points": [[x,y],[x,y]], "color": "#000", "width": 3 }
{ "type": "whiteboard_clear" }
{ "type": "typing", "isTyping": true }
{ "type": "read_receipt", "messageId": "abc123" }
{ "type": "nickname_update", "self": "Babe", "other": "Love" }
{ "type": "location", "lat": 28.6139, "lng": 77.2090 }
{ "type": "location_off" }
{ "type": "spotify_activity", "song": "Blinding Lights", "artist": "The Weeknd", "albumArt": "https://..." }
{ "type": "spotify_stopped" }
```

---

## Constraints & Rules

- Maximum 2 connected clients per relay channel at any time
- No user accounts, no sign-up, no email
- No cloud database — server holds zero persistent data
- No LLM or AI features
- No disappearing messages
- No screenshot detection
- App works offline for reading old messages (SQLite local) but requires internet to send/receive

---

## Out of Scope (Explicitly Excluded)

- Group chats
- Third party account login (Google, Instagram etc)
- AI/LLM reply suggestions
- Disappearing messages
- Screenshot alerts
- Any Instagram API integration
- Web version

---

## Development Priority Order

1. WebSocket relay server (Node.js)
2. Flutter app scaffold + pairing/connection flow
3. Real-time text messaging
4. Nicknames + Settings screen
5. Theme packs
6. Photo sharing
7. Share sheet integration (receive reels/links from other apps)
8. Shared whiteboard
9. Live location sharing
10. Spotify now playing activity
11. Polish — UI, receipts, typing indicator

---

## Feature Notes

- **Nicknames** — fully local, syncs to the other phone so both always see the updated names
- **Themes** — shared/common theme picker, 6 pre-built packs, uses Flutter's ThemeData so it's clean to implement
- **Location** — uses OpenStreetMap so completely free, no Google Maps API key needed, never stored anywhere
- **Spotify** — the only feature needing external auth; each person logs in with their own Spotify account once, then the app polls every 30 seconds and broadcasts the now playing status via the same WebSocket pipe
