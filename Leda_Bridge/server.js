const fs = require("fs");
const { WebSocket, WebSocketServer } = require("ws");
const { execFile } = require("child_process");
const { performance } = require("perf_hooks");

const bridgePort = Number(process.env.LEDA_BRIDGE_PORT || 8765);

const wss = new WebSocketServer({
  port: bridgePort,
  host: "0.0.0.0",
});

let sampleRate = 44100;
let channels = 1;
let audioChunks = [];
let turnTiming = null;

function msBetween(start, end) {
  return (end - start).toFixed(0);
}

function logLatency(label, milliseconds) {
  console.log(`[LATENCY] ${label}: ${milliseconds} ms`);
}

function sendToWatch(socket, type, text = "") {
  if (socket.readyState !== WebSocket.OPEN) {
    console.error("Cannot send to Watch: WebSocket is not open");
    return;
  }

  socket.send(JSON.stringify({ type, text }));
}

function makeWavHeader(dataLength, sampleRate, channels) {
  const bitsPerSample = 32;
  const byteRate = (sampleRate * channels * bitsPerSample) / 8;
  const blockAlign = (channels * bitsPerSample) / 8;

  const header = Buffer.alloc(44);

  header.write("RIFF", 0);
  header.writeUInt32LE(36 + dataLength, 4);
  header.write("WAVE", 8);

  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);

  // 3 = IEEE Float32
  header.writeUInt16LE(3, 20);

  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(bitsPerSample, 34);

  header.write("data", 36);
  header.writeUInt32LE(dataLength, 40);

  return header;
}

function transcribeAudio(socket) {
  const whisperStartedAt = performance.now();

  execFile(
    "whisper",
    [
      "audio.wav",
      "--model",
      "base",
      "--language",
      "English",
      "--output_format",
      "txt",
    ],
    (error, stdout, stderr) => {
      const whisperFinishedAt = performance.now();
      logLatency("Whisper", msBetween(whisperStartedAt, whisperFinishedAt));

      if (turnTiming) {
        turnTiming.whisperFinishedAt = whisperFinishedAt;
      }

      if (error) {
        console.error("Whisper failed:", error.message);
        sendToWatch(socket, "LEDA_ERROR", "I couldn't transcribe that. Tap to try again.");
        return;
      }

      console.log("Whisper finished");

      let transcript;

      try {
        transcript = fs.readFileSync("audio.txt", "utf8").trim();
      } catch (readError) {
        console.error("Could not read transcript:", readError.message);
        sendToWatch(socket, "LEDA_ERROR", "I couldn't read the transcript. Tap to try again.");
        return;
      }

      if (!transcript) {
        console.error("Whisper returned an empty transcript");
        sendToWatch(socket, "LEDA_ERROR", "I didn't hear anything. Tap to try again.");
        return;
      }

      console.log("You:", transcript);

      askLeda(transcript, socket);
    },
  );
}

function askLeda(transcript, socket) {
  console.log("Sending to LEDA:", transcript);
  const openClawStartedAt = performance.now();

  execFile(
    "openclaw",
    [
      "agent",
      "--agent", "main",
      "--message", transcript
    ],
    (error, stdout, stderr) => {
      const openClawFinishedAt = performance.now();
      logLatency("OpenClaw", msBetween(openClawStartedAt, openClawFinishedAt));

      if (turnTiming) {
        turnTiming.openClawFinishedAt = openClawFinishedAt;
      }

      if (error) {
        console.error("OpenClaw failed:", error.message);
        sendToWatch(socket, "LEDA_ERROR", "LEDA couldn't answer. Tap to try again.");
        return;
      }

      const reply = stdout.trim();

      console.log("LEDA:", reply);

      sendToWatch(socket, "LEDA_REPLY", reply);

      if (turnTiming) {
        const replySentAt = performance.now();
        logLatency("STOP_AUDIO → reply sent", msBetween(turnTiming.stopReceivedAt, replySentAt));
        console.log("[LATENCY] ---- turn complete ----");
      }
    }
  );
}

wss.on("connection", (socket) => {
  console.log("Apple Watch connected!");

  sendToWatch(socket, "CONNECTED");

  audioChunks = [];

  socket.on("message", (data, isBinary) => {
    // 1. Binary messages = actual microphone audio
    if (isBinary) {
      audioChunks.push(data);
      return;
    }

    // 2. Everything below here is a text command
    const message = data.toString();

    // Audio format message
    if (message.startsWith("AUDIO_FORMAT|")) {
      const parts = message.split("|");

      sampleRate = Number(parts[1]);
      channels = Number(parts[2]);

      console.log("🎧 Format:", sampleRate, "Hz,", channels, "channel(s)");

      return;
    }

    // STOP AUDIO
    if (message === "STOP_AUDIO") {
      const stopReceivedAt = performance.now();
      turnTiming = { stopReceivedAt };

      console.log("Audio stream finished");
      console.log("[LATENCY] ---- turn started ----");

      const rawAudio = Buffer.concat(audioChunks);

      if (rawAudio.length === 0) {
        console.log("No audio received");
        sendToWatch(socket, "LEDA_ERROR", "I didn't receive any audio. Tap to try again.");
        return;
      }

      const header = makeWavHeader(rawAudio.length, sampleRate, channels);
      const wav = Buffer.concat([header, rawAudio]);

      try {
        fs.writeFileSync("audio.wav", wav);
      } catch (writeError) {
        console.error("Could not save audio:", writeError.message);
        sendToWatch(socket, "LEDA_ERROR", "I couldn't save that recording. Tap to try again.");
        audioChunks = [];
        return;
      }

      const wavSavedAt = performance.now();
      turnTiming.wavSavedAt = wavSavedAt;
      logLatency("STOP_AUDIO → WAV saved", msBetween(stopReceivedAt, wavSavedAt));

      console.log("Saved audio.wav:", wav.length, "bytes");
      transcribeAudio(socket);

      // Clear old recording so the next conversation starts fresh
      audioChunks = [];

      return;
    }

    // Any other text message
    console.log("Received:", message);
  });

  socket.on("close", () => {
    console.log("Apple Watch disconnected");
  });
});

console.log(`LEDA bridge listening on port ${bridgePort}`);
