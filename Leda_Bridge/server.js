const fs = require("fs");
const { WebSocketServer } = require("ws");
const { execFile } = require("child_process");
const path = require("path");

const wss = new WebSocketServer({
  port: 8765,
  host: "0.0.0.0",
});

let sampleRate = 44100;
let channels = 1;
let audioChunks = [];

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
      if (error) {
        console.error("Whisper failed:", error.message);
        return;
      }

      console.log("Whisper finished");

      const transcript = fs.readFileSync("audio.txt", "utf8").trim();

      console.log("You:", transcript);

      askLeda(transcript, socket);
    },
  );
}

function askLeda(transcript, socket) {
  console.log("Sending to LEDA:", transcript);

  execFile(
    "openclaw",
    [
      "agent",
      "--agent", "main",
      "--message", transcript
    ],
    (error, stdout, stderr) => {
      if (error) {
        console.error("OpenClaw failed:", error.message);
        return;
      }

      const reply = stdout.trim();

      console.log("LEDA:", reply);

      socket.send(
        JSON.stringify({
          type: "LEDA_REPLY",
          text: reply
        })
      );
    }
  );
}

wss.on("connection", (socket) => {
  console.log("Apple Watch connected!");

  audioChunks = [];

  socket.on("message", (data, isBinary) => {
    // 1. Binary messages = actual microphone audio
    if (isBinary) {
      audioChunks.push(data);

      console.log("Audio received:", data.length, "bytes");
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
      console.log("Audio stream finished");

      const rawAudio = Buffer.concat(audioChunks);

      if (rawAudio.length === 0) {
        console.log("No audio received");
        return;
      }

      const header = makeWavHeader(rawAudio.length, sampleRate, channels);

      const wav = Buffer.concat([header, rawAudio]);

      fs.writeFileSync("audio.wav", wav);

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

console.log("LEDA bridge listening on port 8765");
