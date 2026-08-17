const fs = require("fs");
const { WebSocketServer } = require("ws");

const wss = new WebSocketServer({
  port: 8765,
  host: "0.0.0.0"
});

let sampleRate = 44100;
let channels = 1;
let audioChunks = [];

wss.on("connection", socket => {
  console.log("⌚ Apple Watch connected!");

  audioChunks = [];

  socket.on("message", (data, isBinary) => {

    if (!isBinary) {
      const message = data.toString();

      if (message.startsWith("AUDIO_FORMAT|")) {
        const parts = message.split("|");

        sampleRate = Number(parts[1]);
        channels = Number(parts[2]);

        console.log("🎧 Format:", sampleRate, "Hz,", channels, "channel(s)");
        return;
      }

      console.log("Received:", message);
      return;
    }

    audioChunks.push(data);

    console.log("🎤 Audio:", data.length, "bytes");
  });

  socket.on("close", () => {
    console.log("Watch disconnected");

    const rawAudio = Buffer.concat(audioChunks);

    fs.writeFileSync("audio.raw", rawAudio);

    console.log("💾 Saved audio.raw:", rawAudio.length, "bytes");
  });
});

console.log("LEDA bridge listening on port 8765");