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

enum SocketState {
    case disconnected
    case connecting
    case connected
    case failed
}

struct ClassicAlien: Identifiable {
    let id: String
    let name: String
    let assetName: String

    static let originalTen = [
        ClassicAlien(id: "heatblast", name: "HEATBLAST", assetName: "AlienHeatblast"),
        ClassicAlien(id: "wildmutt", name: "WILDMUTT", assetName: "AlienWildmutt"),
        ClassicAlien(id: "diamondhead", name: "DIAMONDHEAD", assetName: "AlienDiamondhead"),
        ClassicAlien(id: "xlr8", name: "XLR8", assetName: "AlienXLR8"),
        ClassicAlien(id: "grey-matter", name: "GREY MATTER", assetName: "AlienGreyMatter"),
        ClassicAlien(id: "four-arms", name: "FOUR ARMS", assetName: "AlienFourArms"),
        ClassicAlien(id: "stinkfly", name: "STINKFLY", assetName: "AlienStinkfly"),
        ClassicAlien(id: "ripjaws", name: "RIPJAWS", assetName: "AlienRipjaws"),
        ClassicAlien(id: "upgrade", name: "UPGRADE", assetName: "AlienUpgrade"),
        ClassicAlien(id: "ghostfreak", name: "GHOSTFREAK", assetName: "AlienGhostfreak"),
    ]
}

struct ContentView: View {

    private let bridgeURL = URL(string: "ws://Anshumans-MacBook-Air.local:8765")!
    
    @State private var ledaState: LedaState = .idle
    @State private var rotation = 0.0
    @State private var scale = 1.0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioEngine = AVAudioEngine()
    @State private var webSocketTask: URLSessionWebSocketTask?
    @State private var didSendAudioFormat = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var speechDelegate = SpeechDelegate()
    @State private var isRecording = false
    @State private var socketState: SocketState = .disconnected
    @State private var errorMessage: String?
    @State private var isChoosingAlien = true
    @State private var selectedAlienIndex = 0

    private var selectedAlien: ClassicAlien {
        ClassicAlien.originalTen[selectedAlienIndex]
    }
    
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
            isRecording = true

            print("LEDA microphone LIVE")

        } catch {
            print("Audio error:", error)
            ledaState = .idle
        }
    }
    
    func stopLiveAudio() {
        guard isRecording else {
            print("LEDA microphone was not running")
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        isRecording = false
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
        if socketState == .connected {
            if ledaState == .listening && !isRecording {
                startLiveAudio()
            }
            return
        }

        guard socketState != .connecting else {
            print("Socket state:", socketState)
            return
        }

        socketState = .connecting
        errorMessage = nil

        let request = URLRequest(url: bridgeURL, timeoutInterval: 8)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveFromLeda()

        print("Connecting to LEDA bridge...")
    }
    
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard socketState == .connected else {
            return
        }

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

                        if message.type == "CONNECTED" {
                            Task { @MainActor in
                                socketState = .connected
                                print("✅ LEDA bridge connected")

                                if ledaState == .listening && !isRecording {
                                    startLiveAudio()
                                }
                            }
                        }

                        if message.type == "LEDA_REPLY" {
                            Task { @MainActor in
                                errorMessage = nil
                                ledaState = .speaking
                                speak(message.text)
                            }
                        }

                        if message.type == "LEDA_ERROR" {
                            Task { @MainActor in
                                errorMessage = message.text
                                ledaState = .idle
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

                Task { @MainActor in
                    if isRecording {
                        audioEngine.inputNode.removeTap(onBus: 0)
                        audioEngine.stop()
                        isRecording = false
                        didSendAudioFormat = false
                    }

                    socketState = .failed
                    webSocketTask = nil

                    if ledaState == .listening {
                        ledaState = .idle
                    }
                }
            }
        }
    }

    func selectAlien(at index: Int) {
        selectedAlienIndex = index
        isChoosingAlien = false
        errorMessage = nil

        WKInterfaceDevice.current().play(.click)
        playActivationSound()

        withAnimation(.easeInOut(duration: 0.35)) {
            scale = 1.18
            rotation += 180
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            beginConversation()

            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                scale = 1.0
            }
        }
    }

    func beginConversation() {
        guard ledaState == .idle else {
            return
        }

        errorMessage = nil
        ledaState = .listening
        connectToLedaBridge()
    }

    func handleOmnitrixTap() {
        switch ledaState {
        case .idle:
            beginConversation()

        case .listening:
            if isRecording {
                ledaState = .thinking
                stopLiveAudio()
            }

        default:
            break
        }
    }

    var stateLabel: String {
        switch ledaState {
        case .idle:
            return selectedAlien.name
        case .listening:
            return "LISTENING"
        case .thinking:
            return "THINKING"
        case .speaking:
            return "LEDA"
        }
    }
    
    var body: some View {
        ZStack {
            Color.black

            if isChoosingAlien {
                AlienSelectorView(selectedIndex: $selectedAlienIndex) { index in
                    selectAlien(at: index)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                ZStack {
                    Circle()
                        .stroke(omnitrixColor.opacity(0.35), lineWidth: 14)
                        .frame(width: 146, height: 146)

                    Circle()
                        .fill(omnitrixColor)
                        .frame(width: 128, height: 128)

                    DiamondShape()
                        .fill(Color.black.opacity(0.9))
                        .frame(width: 88, height: 112)
                        .rotationEffect(.degrees(rotation))

                    Image(selectedAlien.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 108)
                        .shadow(color: .black.opacity(0.8), radius: 2, y: 2)
                }
                .scaleEffect(scale)
                .contentShape(Circle())
                .onTapGesture {
                    handleOmnitrixTap()
                }
                .transition(.opacity.combined(with: .scale(scale: 1.12)))

                VStack {
                    HStack {
                        Button {
                            guard ledaState == .idle else {
                                return
                            }

                            withAnimation(.easeInOut(duration: 0.25)) {
                                isChoosingAlien = true
                            }
                        } label: {
                            Image(systemName: "circle.grid.3x3.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(ledaState != .idle)
                        .opacity(ledaState == .idle ? 1 : 0.25)

                        Spacer()
                    }

                    Spacer()

                    Text(stateLabel)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(omnitrixColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

                if socketState == .connecting {
                    ProgressView()
                        .controlSize(.mini)
                        .offset(y: 78)
                } else if socketState == .failed {
                    Text("Bridge unavailable. Tap to retry.")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .offset(y: 78)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .offset(y: 78)
                }
            }
        }
    }
}

struct AlienSelectorView: View {
    @Binding var selectedIndex: Int
    let onSelect: (Int) -> Void

    @State private var crownPosition = 0.0
    @State private var isScanning = false
    @FocusState private var isCrownFocused: Bool

    private var selectedAlien: ClassicAlien {
        ClassicAlien.originalTen[selectedIndex]
    }

    var body: some View {
        VStack(spacing: 1) {
            Text("SELECT ALIEN")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.green)
                .tracking(1.2)

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.07))
                    .frame(width: 154, height: 154)

                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.green, .black, .green, .black, .green],
                            center: .center
                        ),
                        lineWidth: 9
                    )
                    .frame(width: 148, height: 148)

                ZStack {
                    ForEach(0..<ClassicAlien.originalTen.count, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedIndex ? Color.white : Color.green.opacity(0.5))
                            .frame(
                                width: index == selectedIndex ? 4 : 2,
                                height: index == selectedIndex ? 14 : 9
                            )
                            .offset(y: -72)
                            .rotationEffect(
                                .degrees(
                                    Double(index) * 36
                                )
                            )
                    }
                }
                .rotationEffect(.degrees(Double(-selectedIndex) * 36))
                .animation(.spring(response: 0.32, dampingFraction: 0.7), value: selectedIndex)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.9), Color.green.opacity(0.28), .black],
                            center: .center,
                            startRadius: 12,
                            endRadius: 70
                        )
                    )
                    .frame(width: 128, height: 128)

                DiamondShape()
                    .fill(Color.black.opacity(0.88))
                    .frame(width: 87, height: 112)

                Image(selectedAlien.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 112)
                    .id(selectedAlien.id)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.55).combined(with: .opacity),
                            removal: .scale(scale: 1.35).combined(with: .opacity)
                        )
                    )
                    .shadow(color: .green.opacity(0.65), radius: 5)

                Rectangle()
                    .fill(Color.green.opacity(0.75))
                    .frame(width: 94, height: 2)
                    .blur(radius: 0.5)
                    .offset(y: isScanning ? 48 : -48)
                    .animation(
                        .linear(duration: 1.05).repeatForever(autoreverses: true),
                        value: isScanning
                    )
                    .mask {
                        Circle()
                            .frame(width: 116, height: 116)
                    }

                HStack {
                    Image(systemName: "chevron.left")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.green.opacity(0.8))
                .frame(width: 170)
            }

            Text(selectedAlien.name)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("TURN CROWN  •  TAP TO SELECT")
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(.green.opacity(0.78))
                .tracking(0.35)
        }
        .contentShape(Rectangle())
        .focusable()
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $crownPosition,
            from: 0,
            through: Double(ClassicAlien.originalTen.count - 1),
            by: 1,
            sensitivity: .medium,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownPosition) { _, newValue in
            let newIndex = Int(newValue.rounded())

            guard newIndex != selectedIndex,
                  ClassicAlien.originalTen.indices.contains(newIndex) else {
                return
            }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.68)) {
                selectedIndex = newIndex
            }
        }
        .onTapGesture {
            onSelect(selectedIndex)
        }
        .onAppear {
            crownPosition = Double(selectedIndex)
            isCrownFocused = true
            isScanning = true
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

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
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
