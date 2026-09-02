import Foundation
import AVFoundation
import Observation

@Observable
final class RealtimeLedaController {

    private let audioManager: AudioManager
    private let socketClient: LedaSocketClient
    private let audioPlayer: RealtimeAudioPlayer

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

        configureCallbacks()
    }

    func beginConversation() {
        guard ledaState == .idle else {
            return
        }

        errorMessage = nil
        latestTranscript = ""
        ledaState = .listening

        if socketClient.state == .connected {
            socketState = .connected
            startAudioIfNeeded()
        } else {
            socketClient.connect()
        }
    }

    func endConversation() {
        if audioManager.isRecording {
            audioManager.stop()
        }

        socketClient.send(text: "CLOSE_REALTIME")
        audioPlayer.stop()
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
                self?.errorMessage = "Microphone unavailable: \(error.localizedDescription)"
                self?.ledaState = .idle
            }
        }

        socketClient.onStateChange = { [weak self] newState in
            Task { @MainActor in
                self?.socketState = newState

                if newState == .connected {
                    self?.startAudioIfNeeded()
                }
            }
        }

        socketClient.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handle(message)
            }
        }

        socketClient.onBinaryData = { [weak self] data in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.ledaState = .speaking
                self.audioPlayer.play(data)
            }
        }

        socketClient.onFailure = { [weak self] error in
            Task { @MainActor in
                guard let self else {
                    return
                }

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

        audioManager.start()
    }

    private func sendAudioFormat(_ format: AVAudioFormat) {
        let info = """
        AUDIO_FORMAT|\(format.sampleRate)|\(format.channelCount)|\(format.commonFormat.rawValue)|\(format.isInterleaved)
        """

        socketClient.send(text: info)
    }

    private func sendAudioData(_ data: Data) {
        guard socketClient.state == .connected else {
            return
        }

        socketClient.send(data: data)
    }

    private func handle(_ message: LedaMessage) {
        switch message.type {
        case "REALTIME_READY":
            errorMessage = nil
            if ledaState != .speaking {
                ledaState = .listening
            }

        case "REALTIME_TRANSCRIPT":
            latestTranscript = message.text

        case "REALTIME_AUDIO_DONE":
            if ledaState == .speaking {
                ledaState = .listening
            }

        case "REALTIME_CLEAR_AUDIO":
            audioPlayer.clear()
            ledaState = .listening

        case "LEDA_ERROR":
            errorMessage = message.text
            ledaState = .idle

        case "REALTIME_CLOSED":
            if audioManager.isRecording {
                audioManager.stop()
            }
            audioPlayer.stop()
            ledaState = .idle

        default:
            break
        }
    }
}
