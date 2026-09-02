import Foundation

final class LedaSocketClient {

    private let bridgeURL = URL(string: "ws://Anshumans-MacBook-Air.local:8765")!

    private var webSocketTask: URLSessionWebSocketTask?

    private(set) var state: SocketState = .disconnected
}
