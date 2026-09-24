# LEDA for watchOS

A watch-first voice assistant experiment built around a custom Omnitrix-inspired interface, real-time microphone streaming, and spoken AI responses.

The project explores what it takes to make a conversational assistant feel native on Apple Watch rather than like a phone app squeezed onto a smaller screen.

## What it does

- Presents a custom watchOS interface with activation, selection, and listening states
- Captures microphone audio directly on Apple Watch
- Streams audio over WebSockets to a lightweight Node.js bridge
- Plays streamed assistant audio back on the watch
- Coordinates UI, audio, socket, and conversation state in Swift
- Includes sound cues and animated interaction states for a more physical, device-like feel

## Architecture

```text
Apple Watch
  │
  │ microphone audio
  ▼
AVAudioEngine / AVFoundation
  │
  │ PCM over WebSocket
  ▼
Node.js realtime bridge
  │
  │ realtime AI session
  ▼
Assistant response audio
  │
  ▼
WebSocket stream
  │
  ▼
Apple Watch playback
```

## Tech

**watchOS:** Swift, SwiftUI, WatchKit, AVFoundation, AVAudioEngine  
**Realtime transport:** WebSockets  
**Bridge:** Node.js  
**Audio:** live microphone capture + streamed playback

## Repository structure

```text
LedaWatchOS/
├── LedaWatchOS Watch App/
│   ├── ContentView.swift
│   ├── LedaController.swift
│   ├── LedaSocketClient.swift
│   ├── RealtimeLedaController.swift
│   ├── RealtimeAudioPlayer.swift
│   └── AudioManager.swift
└── LedaWatchOS.xcodeproj/

Leda_Bridge/
├── realtime-server.mjs
├── server.js
└── package.json
```

## Why I built it

Most voice assistants treat the watch as a secondary surface. I wanted to prototype the opposite: a small wearable interface where voice, sound, animation, and low-latency feedback are the primary interaction model.

The project has been useful for learning the lower-level details behind realtime audio systems on Apple platforms: audio-session configuration, input taps, PCM streaming, WebSocket state, playback buffering, and coordinating asynchronous UI state.

## Status

Active prototype. The core watch-to-bridge realtime path is implemented; the project is still evolving as I refine reliability, latency, and the interaction model.
