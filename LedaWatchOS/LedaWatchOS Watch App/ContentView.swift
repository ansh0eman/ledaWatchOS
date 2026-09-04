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
    @State private var controller = RealtimeLedaController()
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isChoosingAlien = false
    @State private var isTransforming = false
    @State private var isRecharging = false
    @State private var selectedAlienIndex = 0
    @State private var transformationPulse = false

    private var selectedAlien: ClassicAlien {
        ClassicAlien.originalTen[selectedAlienIndex]
    }

    private var accentColor: Color {
        isRecharging ? .red : Color(red: 0.35, green: 1.0, blue: 0.12)
    }

    private var statusText: String {
        if isRecharging { return "RECHARGING" }
        if isTransforming { return "DNA LOCK" }

        switch controller.ledaState {
        case .idle: return "READY"
        case .listening: return "LISTENING"
        case .thinking: return "PROCESSING"
        case .speaking: return "LEDA"
        }
    }

    func playSound(named resourceName: String) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Could not play \(resourceName):", error)
        }
    }

    func selectAlien(at index: Int) {
        selectedAlienIndex = index
        isChoosingAlien = false
        isTransforming = true
        transformationPulse = false
        controller.clearError()

        WKInterfaceDevice.current().play(.click)
        playSound(named: "alien-confirm")

        withAnimation(.easeOut(duration: 0.16)) {
            transformationPulse = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            WKInterfaceDevice.current().play(.success)
            playSound(named: "ben10-short")

            withAnimation(.easeInOut(duration: 0.30)) {
                transformationPulse = false
            }

            controller.beginConversation()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                isTransforming = false
            }
        }
    }

    func endConversationWithRecharge() {
        controller.endConversation()
        isRecharging = true
        WKInterfaceDevice.current().play(.failure)
        playSound(named: "ben10-short")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isRecharging = false
            }
        }
    }

    func handleMainTap() {
        guard !isRecharging, !isTransforming else { return }

        switch controller.ledaState {
        case .idle:
            WKInterfaceDevice.current().play(.click)
            playSound(named: "activation")
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                isChoosingAlien = true
            }

        case .listening, .speaking:
            endConversationWithRecharge()

        case .thinking:
            break
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isChoosingAlien {
                AlienSelectorView(selectedIndex: $selectedAlienIndex, onDial: {
                    playSound(named: "dial-tick")
                }) { index in
                    selectAlien(at: index)
                }
                .transition(.opacity)
            } else {
                OmnitrixFaceView(
                    accentColor: accentColor,
                    statusText: statusText,
                    selectedAlien: selectedAlien,
                    showAlien: controller.ledaState != .idle || isTransforming,
                    isTransforming: isTransforming,
                    transformationPulse: transformationPulse,
                    isSpeaking: controller.ledaState == .speaking,
                    isListening: controller.ledaState == .listening,
                    isRecharging: isRecharging
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    handleMainTap()
                }
            }

            if controller.socketState == .connecting {
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.green)
                        .padding(.bottom, 5)
                }
            }

            if controller.socketState == .failed || controller.errorMessage != nil {
                VStack {
                    Spacer()
                    Text("CONNECTION ERROR")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.red)
                        .tracking(1)
                        .padding(.bottom, 5)
                }
            }
        }
    }
}

struct OmnitrixFaceView: View {
    let accentColor: Color
    let statusText: String
    let selectedAlien: ClassicAlien
    let showAlien: Bool
    let isTransforming: Bool
    let transformationPulse: Bool
    let isSpeaking: Bool
    let isListening: Bool
    let isRecharging: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let faceWidth = width * 0.95
            let faceHeight = height * 0.90

            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.74),
                                Color(white: 0.25),
                                Color(white: 0.08),
                                Color(white: 0.48)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: faceWidth, height: faceHeight)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black)
                    .frame(width: faceWidth - 10, height: faceHeight - 10)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(accentColor.opacity(0.35), lineWidth: 1)
                    }

                OmnitrixBezelShape()
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .square, lineJoin: .round)
                    )
                    .frame(width: faceWidth - 17, height: faceHeight - 17)
                    .shadow(color: accentColor.opacity(0.55), radius: 5)

                if transformationPulse {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [accentColor, accentColor.opacity(0.85), .black],
                                center: .center,
                                startRadius: 8,
                                endRadius: max(width, height) * 0.65
                            )
                        )
                        .frame(width: faceWidth - 12, height: faceHeight - 12)
                        .transition(.opacity)
                }

                if showAlien && !isRecharging {
                    Image(selectedAlien.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: width * 0.48, height: height * 0.60)
                        .opacity(isTransforming ? 0.95 : 0.48)
                        .shadow(color: accentColor.opacity(0.8), radius: isTransforming ? 10 : 5)
                        .scaleEffect(isTransforming ? 1.12 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTransforming)
                }

                OmnitrixHourglassStroke()
                    .stroke(
                        accentColor,
                        style: StrokeStyle(
                            lineWidth: max(8, width * 0.055),
                            lineCap: .square,
                            lineJoin: .miter
                        )
                    )
                    .frame(width: faceWidth * 0.73, height: faceHeight * 0.68)
                    .shadow(color: accentColor.opacity(isSpeaking ? 1.0 : 0.65), radius: isSpeaking ? 9 : 4)
                    .opacity(showAlien && !isRecharging ? 0.30 : 1.0)
                    .scaleEffect(isListening ? 1.02 : 1.0)
                    .animation(
                        isListening ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                        value: isListening
                    )

                VStack(spacing: 0) {
                    HStack {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 6, height: 6)
                            .shadow(color: accentColor, radius: 3)

                        Spacer()

                        Text(statusText)
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(accentColor)
                            .tracking(1.1)
                    }
                    .padding(.horizontal, width * 0.10)
                    .padding(.top, height * 0.085)

                    Spacer()

                    if showAlien && !isRecharging {
                        Text(selectedAlien.name)
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(accentColor.opacity(0.95))
                            .tracking(0.8)
                            .padding(.bottom, height * 0.07)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct AlienSelectorView: View {
    @Binding var selectedIndex: Int
    let onDial: () -> Void
    let onSelect: (Int) -> Void

    @State private var crownPosition = 0.0
    @FocusState private var isCrownFocused: Bool

    private var selectedAlien: ClassicAlien {
        ClassicAlien.originalTen[selectedIndex]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.green.opacity(0.38), lineWidth: 1)
                    .padding(5)

                OmnitrixBezelShape()
                    .stroke(
                        Color(red: 0.35, green: 1.0, blue: 0.12),
                        style: StrokeStyle(lineWidth: 7, lineCap: .square, lineJoin: .round)
                    )
                    .padding(11)
                    .opacity(0.65)

                VStack(spacing: 2) {
                    HStack {
                        Text("DNA SELECT")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(.green)

                        Spacer()

                        Text(String(format: "%02d", selectedIndex + 1))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.7))
                    }
                    .padding(.horizontal, 18)

                    Spacer()

                    ZStack {
                        OmnitrixHourglassStroke()
                            .stroke(Color.green.opacity(0.14), lineWidth: 9)
                            .frame(width: geometry.size.width * 0.62, height: geometry.size.height * 0.52)

                        Image(selectedAlien.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width * 0.46, height: geometry.size.height * 0.50)
                            .id(selectedAlien.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.84)))
                            .shadow(color: .green.opacity(0.85), radius: 7)
                    }

                    Spacer()

                    Text(selectedAlien.name)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.green)
                        .tracking(0.9)

                    Text("CROWN TO SCAN  •  TAP TO LOCK")
                        .font(.system(size: 6.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.green.opacity(0.65))
                        .tracking(0.35)
                        .padding(.bottom, 4)
                }
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

                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
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
            }
        }
    }
}

struct OmnitrixHourglassStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        return path
    }
}

struct OmnitrixBezelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.width * 0.22
        let y = rect.height * 0.22

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + y))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + x, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - x, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + y))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - y))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - x, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - y))

        return path
    }
}

#Preview {
    ContentView()
}
