const http = require("http");
const { WebSocketServer } = require("ws");
const url = require("url");

const PORT = process.env.PORT || 3000;
const MAX_CLIENTS_PER_ROOM = 2;

// Rate limiting: max connections per IP per minute
const RATE_LIMIT_WINDOW = 60000; // 1 minute
const RATE_LIMIT_MAX = 10; // max 10 connection attempts per IP per minute
const connectionAttempts = new Map(); // IP -> [{timestamp}]

// rooms: Map<roomId, Set<ws>>
const rooms = new Map();

function isRateLimited(ip) {
  const now = Date.now();
  if (!connectionAttempts.has(ip)) {
    connectionAttempts.set(ip, []);
  }

  const attempts = connectionAttempts.get(ip);
  // Remove old entries outside the window
  while (attempts.length > 0 && now - attempts[0] > RATE_LIMIT_WINDOW) {
    attempts.shift();
  }

  if (attempts.length >= RATE_LIMIT_MAX) {
    return true;
  }

  attempts.push(now);
  return false;
}

// Clean up rate limit map periodically
setInterval(() => {
  const now = Date.now();
  for (const [ip, attempts] of connectionAttempts.entries()) {
    while (attempts.length > 0 && now - attempts[0] > RATE_LIMIT_WINDOW) {
      attempts.shift();
    }
    if (attempts.length === 0) {
      connectionAttempts.delete(ip);
    }
  }
}, RATE_LIMIT_WINDOW);

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", rooms: rooms.size }));
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server });

wss.on("connection", (ws, req) => {
  // Rate limiting
  const ip = req.headers["x-forwarded-for"]?.split(",")[0]?.trim() || req.socket.remoteAddress;
  if (isRateLimited(ip)) {
    console.log(`[!] Rate limited connection from ${ip}`);
    ws.close(4003, "Rate limited — too many connection attempts");
    return;
  }

  const params = url.parse(req.url, true).query;
  const roomId = params.room;

  if (!roomId) {
    ws.close(4000, "Missing room parameter");
    return;
  }

  // Get or create room
  if (!rooms.has(roomId)) {
    rooms.set(roomId, new Set());
  }

  const room = rooms.get(roomId);

  // Enforce 2-client limit
  if (room.size >= MAX_CLIENTS_PER_ROOM) {
    ws.close(4001, "Room is full");
    return;
  }

  room.add(ws);
  ws.roomId = roomId;

  console.log(`[+] Client joined room "${roomId}" (${room.size}/${MAX_CLIENTS_PER_ROOM}) from ${ip}`);

  // Notify the other client that their partner connected
  for (const client of room) {
    if (client !== ws && client.readyState === 1) {
      client.send(JSON.stringify({ type: "partner_connected" }));
    }
  }

  // Mark connection alive for heartbeat
  ws.isAlive = true;
  ws.on("pong", () => { ws.isAlive = true; });

  ws.on("message", (data) => {
    const str = data.toString();

    // Handle client-level keep-alive pings
    try {
      const parsed = JSON.parse(str);
      if (parsed.type === "ping") {
        ws.send(JSON.stringify({ type: "pong" }));
        return;
      }
    } catch (_) {}

    // Relay to the other client in the same room
    // Server never reads the encrypted payload — just forwards it blindly
    const room = rooms.get(ws.roomId);
    if (!room) return;

    for (const client of room) {
      if (client !== ws && client.readyState === 1) {
        client.send(str);
      }
    }
  });

  ws.on("close", () => {
    const room = rooms.get(ws.roomId);
    if (room) {
      room.delete(ws);
      console.log(`[-] Client left room "${ws.roomId}" (${room.size}/${MAX_CLIENTS_PER_ROOM})`);

      // Notify the remaining client
      for (const client of room) {
        if (client.readyState === 1) {
          client.send(JSON.stringify({ type: "partner_disconnected" }));
        }
      }

      // Clean up empty rooms
      if (room.size === 0) {
        rooms.delete(ws.roomId);
        console.log(`[x] Room "${ws.roomId}" deleted (empty)`);
      }
    }
  });

  ws.on("error", (err) => {
    console.error(`[!] WebSocket error in room "${ws.roomId}":`, err.message);
  });
});

// Server-side heartbeat: detect and clean up dead connections
const HEARTBEAT_INTERVAL = 30000; // 30 seconds
setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      console.log(`[!] Terminating dead connection in room "${ws.roomId}"`);
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, HEARTBEAT_INTERVAL);

server.listen(PORT, () => {
  console.log(`Relay server running on port ${PORT}`);
});
