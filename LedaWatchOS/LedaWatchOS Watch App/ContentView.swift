//
//  ContentView.swift
//  LedaWatchOS Watch App
//
//  Created by Anshuman on 17/08/26.
//

import SwiftUI
import WatchKit
import AVFoundation

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

    @State private var controller = LedaController()
    @State private var rotation = 0.0
    @State private var scale = 1.0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var speechDelegate = SpeechDelegate()
    @State private var isChoosingAlien = false
    @State private var isTransforming = false
    @State private var selectedAlienIndex = 0

    private var selectedAlien: ClassicAlien {
        ClassicAlien.originalTen[selectedAlienIndex]
    }

    var omnitrixColor: Color {
        switch controller.ledaState {
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
                controller.finishSpeaking()
                isTransforming = false
                playSound(named: "ben10-short")
            }
        }

        let utterance = AVSpeechUtterance(string: text)

        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0

        speechSynthesizer.speak(utterance)
    }

    func playSound(named resourceName: String) {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "mp3"
        ) else {
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Could not play \(resourceName):", error)
        }
    }

    func playActivationSound() {
        playSound(named: "activation")
    }

    func selectAlien(at index: Int) {
        selectedAlienIndex = index
        isChoosingAlien = false
        isTransforming = true
        controller.clearError()

        WKInterfaceDevice.current().play(.click)
        playSound(named: "alien-confirm")

        withAnimation(.easeInOut(duration: 0.35)) {
            scale = 1.18
            rotation += 180
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            playSound(named: "ben10-short")
            controller.beginConversation()
            isTransforming = false

            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                scale = 1.0
            }
        }
    }

    func handleOmnitrixTap() {
        switch controller.ledaState {
        case .idle:
            withAnimation(.easeInOut(duration: 0.25)) {
                isChoosingAlien = true
            }
            WKInterfaceDevice.current().play(.click)
            playActivationSound()

        case .listening:
            if controller.isRecording {
                playSound(named: "ben10-short")
                controller.stopListening()
            }

        default:
            break
        }
    }

    var stateLabel: String {
        switch controller.ledaState {
        case .idle:
            return ""
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
                AlienSelectorView(selectedIndex: $selectedAlienIndex, onDial: {
                    playSound(named: "dial-tick")
                }) { index in
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

                    if controller.ledaState == .idle && !isTransforming {
                        ZStack {
                            Circle()
                                .stroke(Color.black.opacity(0.55), lineWidth: 5)
                                .frame(width: 104, height: 104)

                            Circle()
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                .frame(width: 93, height: 93)

                            HourglassShape()
                                .fill(Color.black)
                                .overlay {
                                    HourglassShape()
                                        .stroke(Color.black.opacity(0.9), lineWidth: 3)
                                }
                                .shadow(color: Color.green.opacity(0.85), radius: 7)
                                .frame(width: 72, height: 82)
                        }
                    } else {
                        ZStack {
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
                    }
                }
                .scaleEffect(scale)
                .contentShape(Circle())
                .onTapGesture {
                    handleOmnitrixTap()
                }
                .transition(.opacity.combined(with: .scale(scale: 1.12)))

                VStack {
                    Spacer()

                    if !stateLabel.isEmpty {
                        Text(stateLabel)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(omnitrixColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

                if controller.socketState == .connecting {
                    ProgressView()
                        .controlSize(.mini)
                        .offset(y: 78)
                } else if controller.socketState == .failed {
                    Text("Bridge unavailable. Tap to retry.")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .offset(y: 78)
                } else if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .offset(y: 78)
                }
            }
        }
        .onAppear {
            controller.onReply = { text in
                Task { @MainActor in
                    speak(text)
                }
            }
        }
    }
}

struct AlienSelectorView: View {
    @Binding var selectedIndex: Int
    let onDial: () -> Void
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
            onDial()
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
