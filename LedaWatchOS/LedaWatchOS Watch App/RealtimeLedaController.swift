import Foundation
import AVFoundation
import Observation

@Observable
final class RealtimeLedaController {

    private let audioManager: AudioManager
    private let socketClient: LedaSocketClient
    private let audioPlayer: RealtimeAudioPlayer

    @ObservationIgnored
    private var resumeListeningTask: Task<Void, Never>?

    private(set) var ledaState: LedaState = .idle
    private(set) var socketState: SocketState = .disconnected
    private(set) var errorMessage: String?
    private(set) var latestTranscript: String = ""

    var isRecording: Bool {
        audioManager.isRecording
    }

    init(
        audioManager: AudioManager = AudioManager(),
        socketClient: LedaSocketClient = LedaSocketClient(
            bridgeURL: URL(string: "ws://Anshumans-MacBook-Air.local:8766")!
        ),
        audioPlayer: RealtimeAudioPlayer = RealtimeAudioPlayer()
    ) {
        self.audioManager = audioManager
        self.socketClient = socketClient
        self.audioPlayer = audioPlayer

        print("🚀 Prototype 2 controller initialized")
        print("🌐 Realtime bridge target: ws://Anshumans-MacBook-Air.local:8766")

        configureCallbacks()
    }

    func beginConversation() {
        guard ledaState == .idle else {
            print("⚠️ Prototype 2 begin ignored; state:", ledaState)
            return
        }

        print("🎙️ Prototype 2 beginConversation()")

        resumeListeningTask?.cancel()
        resumeListeningTask = nil
        errorMessage = nil
        latestTranscript = ""
        ledaState = .listening

        if socketClient.state == .connected {
            print("✅ Reusing existing realtime bridge connection")
            socketState = .connected
            startAudioIfNeeded()
        } else {
            print("🔌 Connecting Watch to Prototype 2 bridge on port 8766")
            socketClient.connect()
        }
    }

    func endConversation() {
        print("🛑 Ending Prototype 2 realtime conversation")

        resumeListeningTask?.cancel()
        resumeListeningTask = nil

        if audioManager.isRecording {
            audioManager.stop()
        }

        audioPlayer.stop()
        socketClient.disconnect()
        socketState = .disconnected
        ledaState = .idle
    }

    func clearError() {
        errorMessage = nil
    }

    private func configureCallbacks() {
        audioManager.onFormat = { [weak self] format in
            self?.sendAudioFormat(format)
        }

        audioManager.onAudioData = { [weak self] data in
            self?.sendAudioData(data)
        }

        audioManager.onFailure = { [weak self] error in
            Task { @MainActor in
                print("❌ Prototype 2 microphone failure:", error)
                self?.errorMessage = "Microphone unavailable: \(error.localizedDescription)"
                self?.ledaState = .idle
            }
        }

        socketClient.onStateChange = { [weak self] newState in
            Task { @MainActor in
                print("🔌 Prototype 2 socket state:", newState)
                self?.socketState = newState

                if newState == .connected {
                    print("✅ Watch connected to Prototype 2 bridge")
                    self?.startAudioIfNeeded()
                }
            }
        }

        socketClient.onMessage = { [weak self] message in
            Task { @MainActor in
                print("📨 Prototype 2 event:", message.type)
                self?.handle(message)
            }
        }

        socketClient.onBinaryData = { [weak self] data in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.resumeListeningTask?.cancel()
                self.resumeListeningTask = nil

                if self.ledaState != .speaking {
                    print("🔇 Pausing microphone while LEDA speaks")
                    if self.audioManager.isRecording {
                        self.audioManager.stop()
                    }
                    self.ledaState = .speaking
                }

                print("🔊 Realtime audio chunk from LEDA:", data.count, "bytes")
                self.audioPlayer.play(data)

                // Some realtime providers/builds do not emit a reliable audioDone event.
                // Reschedule a fallback after every audio chunk. While chunks continue,
                // this task keeps getting cancelled. After the final chunk, it waits for
                // the queued PCM to finish and then safely reopens the microphone.
                self.resumeListeningAfterPlayback()
            }
        }

        socketClient.onFailure = { [weak self] error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                print("❌ Prototype 2 bridge failure:", error)

                self.resumeListeningTask?.cancel()
                self.resumeListeningTask = nil

                if self.audioManager.isRecording {
                    self.audioManager.stop()
                }

                self.audioPlayer.stop()
                self.socketState = .failed
                self.errorMessage = "Realtime bridge unavailable: \(error.localizedDescription)"
                self.ledaState = .idle
            }
        }
    }

    private func startAudioIfNeeded() {
        guard ledaState == .listening,
              !audioManager.isRecording else {
            return
        }

        print("🎤 Starting realtime microphone stream")
        audioManager.start()
    }

    private func sendAudioFormat(_ format: AVAudioFormat) {
        let info = """
        AUDIO_FORMAT|\(format.sampleRate)|\(format.channelCount)|\(format.commonFormat.rawValue)|\(format.isInterleaved)
        """

        print("🎧 Sending Watch audio format:", format.sampleRate, "Hz,", format.channelCount, "channel(s)")
        socketClient.send(text: info)
    }

    private func sendAudioData(_ data: Data) {
        guard socketClient.state == .connected else {
            return
        }

        socketClient.send(data: data)
    }

    private func resumeListeningAfterPlayback() {
        resumeListeningTask?.cancel()

        let delay = audioPlayer.remainingPlaybackDuration() + 0.15
        print(String(format: "⏳ Waiting %.2fs for LEDA audio to finish before reopening mic", delay))

        resumeListeningTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)

            guard !Task.isCancelled,
                  self.ledaState == .speaking,
                  self.socketClient.state == .connected else {
                return
            }

            print("🎤 LEDA finished speaking; reopening microphone")
            self.ledaState = .listening
            self.startAudioIfNeeded()
            self.resumeListeningTask = nil
        }
    }

    private func handle(_ message: LedaMessage) {
        switch message.type {
        case "REALTIME_SESSION_CREATED":
            print("🎙️ OpenClaw realtime Talk session created")

        case "REALTIME_READY":
            print("✅ OpenClaw realtime provider ready")
            errorMessage = nil
            if ledaState != .speaking {
                ledaState = .listening
            }

        case "REALTIME_TRANSCRIPT":
            latestTranscript = message.text
            print("📝 Realtime transcript:", message.text)

        case "REALTIME_AUDIO_DONE":
            print("🔊 LEDA realtime audio stream finished")
            if ledaState == .speaking {
                resumeListeningAfterPlayback()
            }

        case "REALTIME_CLEAR_AUDIO":
            if ledaState == .speaking {
                print("🛡️ Ignoring realtime clear while half-duplex playback is active")
                break
            }

            print("🧹 Clearing queued realtime audio")
            audioPlayer.clear()
            ledaState = .listening

        case "LEDA_ERROR":
            print("❌ Realtime LEDA error:", message.text)
            resumeListeningTask?.cancel()
            resumeListeningTask = nil
            errorMessage = message.text
            ledaState = .idle

        case "REALTIME_CLOSED":
            print("🔒 OpenClaw realtime session closed")
            resumeListeningTask?.cancel()
            resumeListeningTask = nil
            if audioManager.isRecording {
                audioManager.stop()
            }
            audioPlayer.stop()
            socketClient.disconnect()
            socketState = .disconnected
            ledaState = .idle

        default:
            break
        }
    }
}
