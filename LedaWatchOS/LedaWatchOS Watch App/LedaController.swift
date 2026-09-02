import Foundation
import AVFoundation
import Observation

enum LedaState {
    case idle
    case listening
    case thinking
    case speaking
}

@Observable
final class LedaController {

    private let audioManager: AudioManager
    private let socketClient: LedaSocketClient

    private(set) var ledaState: LedaState = .idle
    private(set) var socketState: SocketState = .disconnected
    private(set) var errorMessage: String?

    var isRecording: Bool {
        audioManager.isRecording
    }

    var onReply: ((String) -> Void)?

    init(
        audioManager: AudioManager = AudioManager(),
        socketClient: LedaSocketClient = LedaSocketClient()
    ) {
        self.audioManager = audioManager
        self.socketClient = socketClient
        configureCallbacks()
    }

    func beginConversation() {
        guard ledaState == .idle else {
            return
        }

        errorMessage = nil
        ledaState = .listening
        connectIfNeeded()
    }

    func stopListening() {
        guard ledaState == .listening,
              audioManager.isRecording else {
            return
        }

        ledaState = .thinking
        audioManager.stop()

        socketClient.send(text: "STOP_AUDIO") { error in
            if let error {
                print("STOP_AUDIO send error:", error)
            } else {
                print("Told Mac to save audio")
            }
        }
    }

    func finishSpeaking() {
        ledaState = .idle
    }

    func clearError() {
        errorMessage = nil
    }

    private func connectIfNeeded() {
        if socketClient.state == .connected {
            socketState = .connected
            startAudioIfNeeded()
            return
        }

        socketClient.connect()
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
                self?.handleAudioFailure(error)
            }
        }

        socketClient.onStateChange = { [weak self] newState in
            Task { @MainActor in
                self?.handleSocketStateChange(newState)
            }
        }

        socketClient.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handleLedaMessage(message)
            }
        }

        socketClient.onFailure = { [weak self] error in
            Task { @MainActor in
                self?.handleSocketFailure(error)
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

        socketClient.send(text: info) { error in
            if let error {
                print("Format send error:", error)
            } else {
                print("REAL audio format sent")
            }
        }
    }

    private func sendAudioData(_ data: Data) {
        guard socketClient.state == .connected else {
            return
        }

        socketClient.send(data: data) { error in
            if let error {
                print("Audio send error:", error)
            }
        }
    }

    private func handleSocketStateChange(_ newState: SocketState) {
        socketState = newState

        if newState == .connected {
            print("✅ LEDA bridge connected")
            startAudioIfNeeded()
        }
    }

    private func handleLedaMessage(_ message: LedaMessage) {
        switch message.type {
        case "LEDA_REPLY":
            errorMessage = nil
            ledaState = .speaking
            onReply?(message.text)

        case "LEDA_ERROR":
            errorMessage = message.text
            ledaState = .idle

        default:
            break
        }

        print("Type:", message.type)
        print("LEDA said:", message.text)
    }

    private func handleSocketFailure(_ error: Error) {
        print("Socket failure reached controller:", error)

        if audioManager.isRecording {
            audioManager.stop()
        }

        socketState = .failed

        if ledaState == .listening {
            ledaState = .idle
        }
    }

    private func handleAudioFailure(_ error: Error) {
        print("Audio error reached controller:", error)
        errorMessage = "Microphone unavailable. Tap to try again."
        ledaState = .idle
    }
}
