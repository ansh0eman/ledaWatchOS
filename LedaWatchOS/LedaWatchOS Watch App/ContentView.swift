//
//  ContentView.swift
//  LedaWatchOS Watch App
//
//  Created by Anshuman on 17/08/26.
//

import SwiftUI
import WatchKit
import AVFoundation

nonisolated struct LedaMessage: Codable {
    let type: String
    let text: String
}

enum LedaState {
    case idle
    case listening
    case thinking
    case speaking
}

struct ContentView: View {
    
    @State private var ledaState: LedaState = .idle
    @State private var rotation = 0.0
    @State private var scale = 1.0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioEngine = AVAudioEngine()
    @State private var webSocketTask: URLSessionWebSocketTask?
    @State private var didSendAudioFormat = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var speechDelegate = SpeechDelegate()
    
    var omnitrixColor: Color {
        switch ledaState {
        case .idle:
            return .green

        case .listening:
            return .white

        case .thinking:
            return .yellow

        case .speaking:
            return .cyan
        }
    }
    
    func speak(_ text: String) {
        speechSynthesizer.delegate = speechDelegate

            speechDelegate.onFinish = {
                Task { @MainActor in
                    ledaState = .idle
                }
            }

            let utterance = AVSpeechUtterance(string: text)

            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0

            speechSynthesizer.speak(utterance)
    }
    
    func playActivationSound() {
        guard let url = Bundle.main.url(
            forResource: "activation",
            withExtension: "mp3"
        ) else {
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Could not play sound")
        }
    }
    
    func startLiveAudio() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat)
            try session.setActive(true)

            let input = audioEngine.inputNode
            let format = input.inputFormat(forBus: 0)
            
            print("Sample rate:", format.sampleRate)
            print("Channels:", format.channelCount)
            print("Format:", format.commonFormat)
            print("Interleaved:", format.isInterleaved)

            input.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: format
            ) { buffer, time in
                
                if !didSendAudioFormat {

                    let actualFormat = buffer.format

                    let info = """
                    AUDIO_FORMAT|\(actualFormat.sampleRate)|\(actualFormat.channelCount)|\(actualFormat.commonFormat.rawValue)|\(actualFormat.isInterleaved)
                    """

                    webSocketTask?.send(.string(info)) { error in
                        if let error {
                            print("Format send error:", error)
                        } else {
                            print("REAL audio format sent")
                        }
                    }

                    didSendAudioFormat = true
                }

                sendAudioBuffer(buffer)

            }
            
            audioEngine.prepare()
            try audioEngine.start()

            print("LEDA microphone LIVE")

        } catch {
            print("Audio error:", error)
        }
    }
    
    func stopLiveAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        didSendAudioFormat = false
        
        webSocketTask?.send(.string("STOP_AUDIO")) { error in
            if let error {
                print("STOP_AUDIO send error:", error)
            } else {
                print("Told Mac to save audio")
            }
        }
        print("LEDA microphone OFF")
    }
    
    func connectToLedaBridge() {
        let url = URL(string: "ws://192.168.1.5:8765")!

        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveFromLeda()

        webSocketTask?.send(.string("Hello from Apple Watch")) { error in
            if let error = error {
                print("WebSocket error:", error)
            } else {
                print("Message sent to Mac")
            }
        }
    }
    
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers

        guard let rawData = audioBuffer.mData else {
            return
        }

        let data = Data(
            bytes: rawData,
            count: Int(audioBuffer.mDataByteSize)
        )

        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                print("Audio send error:", error)
            }
        }
    }
    
    func receiveFromLeda() {
        webSocketTask?.receive { result in
            switch result {

            case .success(let message):

                switch message {

                case .string(let text):

                    print("🤖 FROM MAC:", text)

                    guard let data = text.data(using: .utf8) else {
                        return
                    }

                    do {
                        let message = try JSONDecoder()
                            .decode(LedaMessage.self, from: data)
                        
                        if message.type == "LEDA_REPLY" {
                            Task { @MainActor in
                                ledaState = .speaking
                                speak(message.text)
                            }
                        }

                        print("Type:", message.type)
                        print("LEDA said:", message.text)

                    } catch {
                        print("Could not decode LEDA message:", error)
                    }

                case .data(let data):
                    print("📦 Binary response:", data.count)

                @unknown default:
                    break
                }

                // Keep listening for the next message
                receiveFromLeda()

            case .failure(let error):
                print("❌ Receive error:", error)
            }
        }
    }
    
    var body: some View {
        ZStack {
            
            Color.black
            
            ZStack {
                Circle()
                    .fill(omnitrixColor)
                    .frame(width: 135, height: 135)
                
                HourglassShape()
                    .fill(Color.black)
                    .frame(width: 75, height: 75)
            }
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .onTapGesture {
                
                //            WKInterfaceDevice.current().play(.start)
                playActivationSound()
                withAnimation(.easeInOut(duration: 0.3)) {
                    scale = 1.25
                    rotation += 180
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    switch ledaState {

                    case .idle:
                        ledaState = .listening
                        connectToLedaBridge()
                        startLiveAudio()

                    case .listening:
                        ledaState = .thinking
                        stopLiveAudio()

                    default:
                        break
                    }
                    
                    withAnimation(.spring()) {
                        scale = 1.0
                    }
                }
            }
        }
    }
}

struct HourglassShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))

        path.closeSubpath()

        return path
    }
}

final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {

    var onFinish: (() -> Void)?

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        onFinish?()
    }
}


#Preview {
    ContentView()
}
