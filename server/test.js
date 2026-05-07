const WebSocket = require("ws");

const SERVER = "ws://localhost:3000";
const ROOM = "test-room-123";
let passed = 0;
let failed = 0;

function assert(condition, name) {
  if (condition) {
    console.log(`  ✓ ${name}`);
    passed++;
  } else {
    console.log(`  ✗ ${name}`);
    failed++;
  }
}

async function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function runTests() {
  console.log("\n--- Test 1: Two clients can join the same room ---");

  const clientA = new WebSocket(`${SERVER}?room=${ROOM}`);
  await new Promise((r) => clientA.on("open", r));
  assert(clientA.readyState === 1, "Client A connected");

  const clientB = new WebSocket(`${SERVER}?room=${ROOM}`);
  // Client A should receive partner_connected
  const partnerMsg = await new Promise((r) => {
    clientA.on("message", (data) => r(JSON.parse(data.toString())));
    clientB.on("open", () => {});
  });
  assert(clientB.readyState === 1, "Client B connected");
  assert(partnerMsg.type === "partner_connected", "Client A notified of partner");

  console.log("\n--- Test 2: Messages relay between clients ---");

  const msgFromA = { type: "text", content: "Hello from A", timestamp: Date.now() };
  const receivedByB = new Promise((r) => {
    clientB.on("message", (data) => r(JSON.parse(data.toString())));
  });
  clientA.send(JSON.stringify(msgFromA));
  const resultB = await receivedByB;
  assert(resultB.content === "Hello from A", "Client B received message from A");

  const msgFromB = { type: "text", content: "Hello from B", timestamp: Date.now() };
  const receivedByA = new Promise((r) => {
    clientA.on("message", (data) => r(JSON.parse(data.toString())));
  });
  clientB.send(JSON.stringify(msgFromB));
  const resultA = await receivedByA;
  assert(resultA.content === "Hello from B", "Client A received message from B");

  console.log("\n--- Test 3: Third client is rejected ---");

  const clientC = new WebSocket(`${SERVER}?room=${ROOM}`);
  const closeInfo = await new Promise((r) => {
    clientC.on("close", (code, reason) => r({ code, reason: reason.toString() }));
  });
  assert(closeInfo.code === 4001, "Third client rejected with code 4001");
  assert(closeInfo.reason === "Room is full", "Rejection reason is 'Room is full'");

  console.log("\n--- Test 4: Missing room param is rejected ---");

  const clientD = new WebSocket(SERVER);
  const closeD = await new Promise((r) => {
    clientD.on("close", (code, reason) => r({ code, reason: reason.toString() }));
  });
  assert(closeD.code === 4000, "No-room client rejected with code 4000");

  console.log("\n--- Test 5: Disconnect notifies partner ---");

  const disconnectMsg = new Promise((r) => {
    clientA.on("message", (data) => r(JSON.parse(data.toString())));
  });
  clientB.close();
  const dcResult = await disconnectMsg;
  assert(dcResult.type === "partner_disconnected", "Client A notified of partner disconnect");

  await sleep(200);
  clientA.close();

  console.log("\n--- Test 6: Health endpoint ---");

  const resp = await fetch("http://localhost:3000/health");
  const body = await resp.json();
  assert(body.status === "ok", "Health endpoint returns ok");

  console.log(`\n=== Results: ${passed} passed, ${failed} failed ===\n`);
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch((err) => {
  console.error("Test error:", err);
  process.exit(1);
});
