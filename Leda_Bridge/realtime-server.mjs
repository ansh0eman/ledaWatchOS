import { randomUUID } from "node:crypto";
import { GatewayClient } from "@openclaw/gateway-client";
import { WebSocket, WebSocketServer } from "ws";

const watchPort = Number(process.env.LEDA_REALTIME_BRIDGE_PORT || 8766);
const gatewayUrl = process.env.OPENCLAW_GATEWAY_URL || "ws://127.0.0.1:18789";
const gatewayToken = process.env.OPENCLAW_GATEWAY_TOKEN;
const gatewayPassword = process.env.OPENCLAW_GATEWAY_PASSWORD;

const TARGET_SAMPLE_RATE = 24000;

const watchServer = new WebSocketServer({
  port: watchPort,
  host: "0.0.0.0",
});

let gatewayReadyResolve;
let gatewayReadyReject;
let gatewayReady = createGatewayReadyPromise();

function createGatewayReadyPromise() {
  const promise = new Promise((resolve, reject) => {
    gatewayReadyResolve = resolve;
    gatewayReadyReject = reject;
  });

  promise.catch(() => {});
  return promise;
}

const watchSessions = new Map();

const gateway = new GatewayClient({
  url: gatewayUrl,
  clientName: "gateway-client",
  clientDisplayName: "LEDA Realtime Bridge",
  clientVersion: "0.2.0",
  platform: "macos",
  mode: "backend",
  role: "operator",
  scopes: ["operator.read", "operator.write"],
  token: gatewayToken,
  password: gatewayPassword,
  deviceIdentity: null,
  onHelloOk: () => {
    console.log("✅ Connected to OpenClaw Gateway");
    gatewayReadyResolve();
  },
  onConnectError: (error) => {
    console.error("❌ OpenClaw Gateway connection failed:", error.message);

    if (!gatewayToken && !gatewayPassword) {
      console.error(
        "No Gateway credential provided. Set OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD before starting the realtime bridge.",
      );
    }

    gatewayReadyReject(error);
  },
  onClose: (code, reason) => {
    console.log(`OpenClaw Gateway closed (${code}): ${reason}`);
    gatewayReady = createGatewayReadyPromise();
  },
  onEvent: (event) => {
    if (event.event !== "talk.event") {
      return;
    }

    forwardTalkEvent(event.payload);
  },
});

gateway.start();

function sendJson(socket, type, text = "", extra = {}) {
  if (socket.readyState !== WebSocket.OPEN) {
    return;
  }

  socket.send(JSON.stringify({ type, text, ...extra }));
}

function float32BufferToPcm16_24k(buffer, sourceSampleRate) {
  const byteLength = buffer.byteLength - (buffer.byteLength % 4);
  if (byteLength <= 0) {
    return Buffer.alloc(0);
  }

  const input = new Float32Array(
    buffer.buffer,
    buffer.byteOffset,
    byteLength / 4,
  );

  if (!Number.isFinite(sourceSampleRate) || sourceSampleRate <= 0) {
    throw new Error(`Invalid Watch sample rate: ${sourceSampleRate}`);
  }

  const outputLength = Math.max(
    1,
    Math.floor(input.length * TARGET_SAMPLE_RATE / sourceSampleRate),
  );

  const output = Buffer.allocUnsafe(outputLength * 2);
  const ratio = sourceSampleRate / TARGET_SAMPLE_RATE;

  for (let index = 0; index < outputLength; index += 1) {
    const sourcePosition = index * ratio;
    const leftIndex = Math.min(Math.floor(sourcePosition), input.length - 1);
    const rightIndex = Math.min(leftIndex + 1, input.length - 1);
    const fraction = sourcePosition - leftIndex;

    const sample = input[leftIndex] +
      (input[rightIndex] - input[leftIndex]) * fraction;

    const clamped = Math.max(-1, Math.min(1, sample));
    const pcm16 = clamped < 0
      ? Math.round(clamped * 32768)
      : Math.round(clamped * 32767);

    output.writeInt16LE(pcm16, index * 2);
  }

  return output;
}

async function createRealtimeSession(socket) {
  await gatewayReady;

  const result = await gateway.request("talk.session.create", {
    mode: "realtime",
    transport: "gateway-relay",
    brain: "agent-consult",
    sessionKey: "main",
    idempotencyKey: randomUUID(),
  });

  const sessionId = result.sessionId || result.relaySessionId;

  if (!sessionId) {
    throw new Error("OpenClaw did not return a realtime Talk session id");
  }

  const session = watchSessions.get(socket);
  if (!session) {
    await gateway.request("talk.session.close", { sessionId });
    return;
  }

  session.sessionId = sessionId;
  session.outputSampleRate = result.audio?.outputSampleRateHz || TARGET_SAMPLE_RATE;

  console.log("🎙️ Realtime Talk session created:", sessionId);
  console.log("🎧 OpenClaw audio contract:", result.audio);

  sendJson(socket, "REALTIME_SESSION_CREATED", "", {
    sampleRate: session.outputSampleRate,
  });
}

async function appendWatchAudio(socket, data) {
  const session = watchSessions.get(socket);

  if (!session?.sessionId) {
    return;
  }

  const pcm16 = float32BufferToPcm16_24k(data, session.inputSampleRate);

  if (pcm16.length === 0) {
    return;
  }

  try {
    await gateway.request("talk.session.appendAudio", {
      sessionId: session.sessionId,
      audioBase64: pcm16.toString("base64"),
    });
  } catch (error) {
    console.error("appendAudio failed:", error.message);
    sendJson(socket, "LEDA_ERROR", `Realtime audio failed: ${error.message}`);
  }
}

function forwardTalkEvent(payload) {
  if (!payload || typeof payload !== "object") {
    return;
  }

  const sessionId = payload.sessionId || payload.relaySessionId;
  if (!sessionId) {
    return;
  }

  for (const [socket, session] of watchSessions) {
    if (session.sessionId !== sessionId || socket.readyState !== WebSocket.OPEN) {
      continue;
    }

    switch (payload.type) {
      case "ready":
        console.log("✅ Realtime provider ready");
        sendJson(socket, "REALTIME_READY");
        break;

      case "transcript":
        console.log(
          `[${payload.role || "unknown"}${payload.final ? " final" : ""}]`,
          payload.text || "",
        );
        sendJson(socket, "REALTIME_TRANSCRIPT", payload.text || "", {
          role: payload.role,
          final: Boolean(payload.final),
        });
        break;

      case "audio": {
        const audio = Buffer.from(payload.audioBase64 || "", "base64");
        if (audio.length > 0) {
          socket.send(audio);
        }
        break;
      }

      case "audioDone":
      case "mark":
        sendJson(socket, "REALTIME_AUDIO_DONE");
        break;

      case "clear":
        sendJson(socket, "REALTIME_CLEAR_AUDIO", payload.reason || "");
        break;

      case "error":
        console.error("Realtime Talk error:", payload.message);
        sendJson(socket, "LEDA_ERROR", payload.message || "Realtime Talk failed");
        break;

      case "close":
        sendJson(socket, "REALTIME_CLOSED", payload.reason || "");
        session.sessionId = null;
        break;

      default:
        break;
    }
  }
}

watchServer.on("connection", (socket) => {
  console.log("⌚ Apple Watch connected to Prototype 2 bridge");

  watchSessions.set(socket, {
    sessionId: null,
    inputSampleRate: 44100,
    channels: 1,
    outputSampleRate: TARGET_SAMPLE_RATE,
  });

  sendJson(socket, "CONNECTED");

  createRealtimeSession(socket).catch((error) => {
    console.error("Could not create realtime Talk session:", error.message);
    sendJson(socket, "LEDA_ERROR", `Realtime session failed: ${error.message}`);
  });

  socket.on("message", (data, isBinary) => {
    if (isBinary) {
      void appendWatchAudio(socket, data);
      return;
    }

    const message = data.toString();

    if (message.startsWith("AUDIO_FORMAT|")) {
      const [, sampleRate, channels] = message.split("|");
      const session = watchSessions.get(socket);

      if (session) {
        session.inputSampleRate = Number(sampleRate) || 44100;
        session.channels = Number(channels) || 1;
      }

      console.log(
        `⌚ Watch audio: ${session?.inputSampleRate} Hz, ${session?.channels} channel(s)`,
      );
      return;
    }

    if (message === "STOP_AUDIO") {
      console.log("⌚ Watch stopped sending realtime audio");
      return;
    }

    if (message === "CLOSE_REALTIME") {
      const session = watchSessions.get(socket);
      if (session?.sessionId) {
        void gateway.request("talk.session.close", {
          sessionId: session.sessionId,
        });
      }
    }
  });

  socket.on("close", () => {
    console.log("⌚ Apple Watch disconnected from Prototype 2 bridge");

    const session = watchSessions.get(socket);
    watchSessions.delete(socket);

    if (session?.sessionId) {
      void gateway.request("talk.session.close", {
        sessionId: session.sessionId,
      }).catch((error) => {
        console.error("Could not close Talk session:", error.message);
      });
    }
  });
});

process.on("SIGINT", async () => {
  console.log("\nClosing realtime bridge...");

  for (const session of watchSessions.values()) {
    if (session.sessionId) {
      try {
        await gateway.request("talk.session.close", {
          sessionId: session.sessionId,
        });
      } catch {
        // Best-effort shutdown.
      }
    }
  }

  gateway.stop();
  watchServer.close(() => process.exit(0));
});

console.log(`LEDA Prototype 2 realtime bridge listening on port ${watchPort}`);
console.log(`OpenClaw Gateway: ${gatewayUrl}`);
console.log(
  `Gateway auth: ${gatewayToken || gatewayPassword ? "explicit credential loaded" : "no credential provided"}`,
);
