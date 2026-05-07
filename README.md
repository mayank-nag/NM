# NM — Private 2-Person Messenger

A private messaging app built for just 2 people. No accounts, no cloud storage, no clutter — just a clean, private space to chat, share photos, and send content from other apps.

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

- **Server**: Dumb WebSocket relay — forwards messages, stores nothing
- **App**: Flutter — all data stored locally in SQLite (Drift)

---

## Quick Start

### 1. Deploy the Relay Server

The server is a lightweight Node.js WebSocket relay. Pick any free hosting:

#### Option A: Railway (recommended — easiest)

1. Go to [railway.app](https://railway.app) and sign in with GitHub
2. Click **"New Project"** → **"Deploy from GitHub Repo"**
3. Point it to your repo (or upload the `server/` folder)
4. Railway auto-detects Node.js. Set the start command if needed:
   ```
   node index.js
   ```
5. Set environment variable (optional):
   ```
   PORT=3000
   ```
6. Railway gives you a URL like `https://nm-relay-production.up.railway.app`
7. Your WebSocket URL is: `wss://nm-relay-production.up.railway.app`

#### Option B: Render

1. Go to [render.com](https://render.com) and create a **Web Service**
2. Connect your repo, set root directory to `server/`
3. Build command: `npm install`
4. Start command: `node index.js`
5. Render gives you a URL → your WebSocket URL is `wss://your-app.onrender.com`

> **Note**: Render free tier spins down after inactivity. First message after sleep takes ~30s.

#### Option C: Fly.io

```bash
cd server
fly launch --name nm-relay
fly deploy
```

Your WebSocket URL: `wss://nm-relay.fly.dev`

#### Option D: Run Locally (testing only)

```bash
cd server
npm install
node index.js
```

Server runs on `ws://localhost:3000`. For Android emulator use `ws://10.0.2.2:3000`.

#### Verify Server is Running

```bash
curl https://your-server-url/health
# Should return: {"status":"ok","rooms":0}
```

---

### 2. Build the Android APK

#### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.9+)
- Android SDK (via Android Studio)
- Java 17+

#### Build Steps

```bash
cd app

# Get dependencies
flutter pub get

# Build release APK
flutter build apk --release
```

The APK will be at:
```
app/build/app/outputs/flutter-apk/app-release.apk
```

#### Build a smaller APK (per-architecture)

```bash
flutter build apk --split-per-abi --release
```

This produces 3 smaller APKs:
- `app-arm64-v8a-release.apk` — most modern phones (use this one)
- `app-armeabi-v7a-release.apk` — older phones
- `app-x86_64-release.apk` — emulators

---

### 3. Install & Pair

#### On Phone A:
1. Install the APK (transfer via USB, Google Drive, Telegram, etc.)
2. Open the app
3. Enter your server's WebSocket URL (e.g., `wss://nm-relay-production.up.railway.app`)
4. Tap **"Generate Room Code"** → you'll get a 6-character code like `A3K9XP`
5. Tap **"Connect"**

#### On Phone B:
1. Install the same APK
2. Open the app
3. Enter the **same** server WebSocket URL
4. Enter the room code from Phone A
5. Tap **"Join Room"**

✅ Both phones are now paired and can message each other!

> **Pairing is one-time** — the room code is saved locally. Next time you open the app, it reconnects automatically.

---

## Features

| Feature | Status |
|---------|--------|
| WebSocket relay server | ✅ |
| Pairing via room code | ✅ |
| Real-time text messaging | ✅ |
| Local SQLite storage (Drift) | ✅ |
| Nicknames (synced) | ✅ |
| Settings screen | ✅ |
| 6 Theme packs | ✅ |
| Photo sharing (camera + gallery) | ✅ |
| Share sheet integration | ✅ |
| Shared whiteboard | 🔲 |
| Live location sharing | 🔲 |
| Spotify now playing | 🔲 |
| Typing indicator | 🔲 |
| Read receipts | 🔲 |

### Theme Packs

| Theme | Style |
|-------|-------|
| Default | Clean minimal dark |
| Midnight | Deep black with neon accents |
| Paper | Warm off-white, light mode |
| Forest | Muted greens and earthy tones |
| Retro | Pixel-style, 8-bit with monospace |
| Pastel | Soft pinks and lilacs, light mode |

---

## Project Structure

```
NM/
├── server/                  # WebSocket relay server
│   ├── index.js             # Server code (single file)
│   ├── package.json         # Dependencies (just ws)
│   └── test.js              # Server tests
│
├── app/                     # Flutter app
│   └── lib/
│       ├── main.dart              # Entry point + share listener
│       ├── connection_service.dart # WebSocket connection manager
│       ├── database.dart          # Drift/SQLite schema
│       ├── database.g.dart        # Generated Drift code
│       ├── chat_screen.dart       # Chat UI + message bubbles
│       ├── pairing_screen.dart    # Room code pairing flow
│       ├── settings_screen.dart   # Nicknames, themes, connection
│       ├── theme_provider.dart    # 6 theme packs + Provider
│       └── photo_viewer.dart      # Full-screen photo viewer
│
└── instruction.md           # Feature spec document
```

---

## Troubleshooting

### "Could not connect" on pairing
- Make sure the server is running (check `/health` endpoint)
- Use `wss://` for hosted servers, `ws://` for local
- For Android emulator → localhost is `ws://10.0.2.2:3000`

### Messages not delivering
- Both phones must be connected to the **same room code**
- Check the status indicator in the chat header (blue dot = partner online)

### Photos not sending
- Large photos may be slow over WebSocket (they're base64 encoded)
- Photos are compressed to 1280px max width, 75% quality before sending

### App crashes on first launch (Android)
- Make sure you've built with `--release` flag
- If using a debug build, ensure USB debugging is enabled

---

## Tech Stack

- **App**: Flutter (Dart)
- **Server**: Node.js + `ws`
- **Local DB**: Drift (SQLite)
- **State**: Provider
- **Photos**: image_picker
- **Sharing**: receive_sharing_intent
