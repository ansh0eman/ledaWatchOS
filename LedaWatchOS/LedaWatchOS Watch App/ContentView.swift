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

    var healthMetric: HealthMetric {
        switch id {
        case "heatblast": return .activeEnergy
        case "wildmutt": return .steps
        case "diamondhead": return .restingHeartRate
        case "xlr8": return .heartRate
        case "grey-matter": return .sleep
        case "four-arms": return .workoutMinutes
        case "stinkfly": return .respiratoryRate
        case "ripjaws": return .oxygenSaturation
        case "upgrade": return .heartRateVariability
        case "ghostfreak": return .walkingHeartRate
        default: return .steps
        }
    }
}

struct ContentView: View {

    @State private var controller = RealtimeLedaController()
    @State private var healthManager = HealthDashboardManager()
    @State private var rotation = 0.0
    @State private var scale = 1.0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isChoosingAlien = false
    @State private var isTransforming = false
    @State private var isShowingHealthDashboard = false
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
        isShowingHealthDashboard = true
        controller.clearError()

        WKInterfaceDevice.current().play(.click)
        playSound(named: "alien-confirm")

        withAnimation(.easeInOut(duration: 0.28)) {
            scale = 1.12
            rotation += 180
        }

        healthManager.requestAccessAndLoad(selectedAlien.healthMetric)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isTransforming = false
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
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

        case .listening, .speaking:
            playSound(named: "ben10-short")
            controller.endConversation()

        case .thinking:
            break
        }
    }

    func toggleLedaVoice() {
        switch controller.ledaState {
        case .idle:
            controller.clearError()
            playSound(named: "ben10-short")
            controller.beginConversation()
        case .listening, .speaking:
            playSound(named: "ben10-short")
            controller.endConversation()
        case .thinking:
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
            } else if isShowingHealthDashboard {
                HealthAlienDashboardView(
                    alien: selectedAlien,
                    healthManager: healthManager,
                    ledaState: controller.ledaState,
                    socketState: controller.socketState,
                    onBack: {
                        if controller.ledaState != .idle {
                            controller.endConversation()
                        }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingHealthDashboard = false
                            isChoosingAlien = true
                        }
                    },
                    onRefresh: {
                        healthManager.load(selectedAlien.healthMetric)
                    },
                    onToggleLeda: {
                        toggleLedaVoice()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
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
                    Text("Realtime bridge unavailable. Tap to retry.")
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
    }
}

struct HealthAlienDashboardView: View {
    let alien: ClassicAlien
    let healthManager: HealthDashboardManager
    let ledaState: LedaState
    let socketState: SocketState
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onToggleLeda: () -> Void

    private var voiceColor: Color {
        switch ledaState {
        case .idle: return .green
        case .listening: return .white
        case .thinking: return .yellow
        case .speaking: return .cyan
        }
    }

    private var voiceLabel: String {
        switch ledaState {
        case .idle: return "LEDA"
        case .listening: return "LISTEN"
        case .thinking: return "THINK"
        case .speaking: return "SPEAK"
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .black))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)

                Spacer()

                VStack(spacing: 0) {
                    Text(alien.name)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.green)
                    Text(alien.healthMetric.title)
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .black))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
            }
            .padding(.horizontal, 8)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.green.opacity(0.38), .green.opacity(0.07), .black],
                            center: .center,
                            startRadius: 8,
                            endRadius: 64
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(alien.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 78)
                    .opacity(0.32)
                    .shadow(color: .green.opacity(0.65), radius: 5)

                VStack(spacing: 0) {
                    if healthManager.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.green)
                        Text("SYNCING")
                            .font(.system(size: 7, weight: .black, design: .rounded))
                            .foregroundStyle(.green)
                            .padding(.top, 3)
                    } else if let snapshot = healthManager.snapshot {
                        Text(snapshot.value)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)

                        Text(snapshot.unit)
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(.green)

                        Text(snapshot.detail)
                            .font(.system(size: 6.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .padding(.top, 2)
                    } else {
                        Text("NO DATA")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(healthManager.errorMessage ?? alien.healthMetric.shortDescription)
                            .font(.system(size: 6.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.green.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(width: 92)
                    }
                }
            }

            Text(alien.healthMetric.shortDescription)
                .font(.system(size: 6.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Button(action: onToggleLeda) {
                HStack(spacing: 4) {
                    Image(systemName: ledaState == .idle ? "waveform.circle.fill" : "waveform")
                    Text(voiceLabel)
                        .font(.system(size: 8, weight: .black, design: .rounded))
                }
                .foregroundStyle(voiceColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(voiceColor.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(socketState == .connecting || ledaState == .thinking)
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 4)
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
                            .rotationEffect(.degrees(Double(index) * 36))
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

#Preview {
    ContentView()
}
