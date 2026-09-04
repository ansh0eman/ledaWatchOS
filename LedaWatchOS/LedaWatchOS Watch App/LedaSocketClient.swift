import Foundation

nonisolated struct LedaMessage: Codable {
    let type: String
    let text: String
}

enum SocketState {
    case disconnected
    case connecting
    case connected
    case failed
}

final class LedaSocketClient {

    private let bridgeURL: URL
    private var webSocketTask: URLSessionWebSocketTask?

    private(set) var state: SocketState = .disconnected

    var onStateChange: ((SocketState) -> Void)?
    var onMessage: ((LedaMessage) -> Void)?
    var onBinaryData: ((Data) -> Void)?
    var onFailure: ((Error) -> Void)?

    init(
        bridgeURL: URL = URL(string: "ws://Anshumans-MacBook-Air.local:8765")!
    ) {
        self.bridgeURL = bridgeURL
    }

    func connect() {
        if state == .connected {
            return
        }

        guard state != .connecting else {
            return
        }

        setState(.connecting)

        let request = URLRequest(url: bridgeURL, timeoutInterval: 8)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveNextMessage()

        print("Connecting to LEDA bridge:", bridgeURL)
    }

    func disconnect() {
        print("Disconnecting from LEDA bridge:", bridgeURL)
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        setState(.disconnected)
    }

    func send(text: String, completion: ((Error?) -> Void)? = nil) {
        guard state == .connected else {
            return
        }

        webSocketTask?.send(.string(text)) { error in
            completion?(error)
        }
    }

    func send(data: Data, completion: ((Error?) -> Void)? = nil) {
        guard state == .connected else {
            return
        }

        webSocketTask?.send(.data(data)) { error in
            completion?(error)
        }
    }

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let message):
                handle(message)
                receiveNextMessage()

            case .failure(let error):
                if state == .disconnected {
                    print("🔌 LEDA bridge connection closed")
                    return
                }

                print("❌ Receive error:", error)
                webSocketTask = nil
                setState(.failed)
                onFailure?(error)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            print("🤖 FROM MAC:", text)

            guard let data = text.data(using: .utf8) else {
                return
            }

            do {
                let decodedMessage = try JSONDecoder().decode(LedaMessage.self, from: data)

                if decodedMessage.type == "CONNECTED" {
                    setState(.connected)
                }

                onMessage?(decodedMessage)
            } catch {
                print("Could not decode LEDA message:", error)
            }

        case .data(let data):
            onBinaryData?(data)

        @unknown default:
            break
        }
    }

    private func setState(_ newState: SocketState) {
        state = newState
        onStateChange?(newState)
    }
}
