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

private enum OmnitrixVisualMode {
    case ready
    case selecting
    case transforming
    case active
    case recharge
}

struct ContentView: View {

    @State private var controller = RealtimeLedaController()
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isChoosingAlien = false
    @State private var isTransforming = false
    @State private var isRecharging = false
    @State private var selectedAlienIndex = 0

    @State private var dialRotation = 0.0
    @State private var coreScale = 1.0
    @State private var energyPulse = false
    @State private var ringSpin = false
    @State private var transformFlash = false
    @State private var rechargePulse = false

    private let activeGreen = Color(red: 0.35, green: 1.0, blue: 0.05)
    private let deepGreen = Color(red: 0.05, green: 0.28, blue: 0.02)
    private let rechargeRed = Color(red: 1.0, green: 0.08, blue: 0.05)

    private var selectedAlien: ClassicAlien {
        ClassicAlien.originalTen[selectedAlienIndex]
    }

    private var visualMode: OmnitrixVisualMode {
        if isRecharging { return .recharge }
        if isTransforming { return .transforming }
        if isChoosingAlien { return .selecting }
        if controller.ledaState == .idle { return .ready }
        return .active
    }

    private var coreColor: Color {
        visualMode == .recharge ? rechargeRed : activeGreen
    }

    private var stateLabel: String {
        if isRecharging { return "RECHARGING" }
        if isTransforming { return "TRANSFORMING" }

        switch controller.ledaState {
        case .idle:
            return "READY"
        case .listening:
            return "LISTENING"
        case .thinking:
            return "PROCESSING"
        case .speaking:
            return "LEDA"
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

    private func startRechargeSequence() {
        isRecharging = true
        rechargePulse = false

        WKInterfaceDevice.current().play(.failure)

        withAnimation(.easeInOut(duration: 0.24).repeatCount(6, autoreverses: true)) {
            rechargePulse = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                isRecharging = false
                rechargePulse = false
            }
        }
    }

    func selectAlien(at index: Int) {
        selectedAlienIndex = index
        isChoosingAlien = false
        isTransforming = true
        transformFlash = false
        controller.clearError()

        WKInterfaceDevice.current().play(.click)
        playSound(named: "alien-confirm")

        withAnimation(.easeIn(duration: 0.18)) {
            coreScale = 1.16
            dialRotation += 180
            transformFlash = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            WKInterfaceDevice.current().play(.success)
            withAnimation(.easeOut(duration: 0.22)) {
                coreScale = 1.34
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            playSound(named: "ben10-short")
            controller.beginConversation()

            withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
                coreScale = 1.0
                transformFlash = false
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                isTransforming = false
            }
        }
    }

    func handleOmnitrixTap() {
        if isRecharging || isTransforming {
            return
        }

        switch controller.ledaState {
        case .idle:
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                isChoosingAlien = true
            }
            WKInterfaceDevice.current().play(.click)
            playSound(named: "activation")

        case .listening, .speaking:
            playSound(named: "ben10-short")
            controller.endConversation()
            startRechargeSequence()

        case .thinking:
            break
        }
    }

    var body: some View {
        ZStack {
            OmnitrixBackdrop(
                color: coreColor,
                energized: visualMode == .active || visualMode == .transforming,
                pulse: energyPulse
            )
            .ignoresSafeArea()

            if isChoosingAlien {
                AlienSelectorView(
                    selectedIndex: $selectedAlienIndex,
                    accent: activeGreen,
                    onDial: { playSound(named: "dial-tick") },
                    onSelect: { selectAlien(at: $0) }
                )
                .transition(.scale(scale: 0.82).combined(with: .opacity))
            } else {
                VStack(spacing: 2) {
                    Spacer(minLength: 0)

                    OmnitrixCoreView(
                        visualMode: visualMode,
                        accent: coreColor,
                        activeGreen: activeGreen,
                        deepGreen: deepGreen,
                        rechargeRed: rechargeRed,
                        selectedAlien: selectedAlien,
                        ledaState: controller.ledaState,
                        dialRotation: dialRotation,
                        ringSpin: ringSpin,
                        transformFlash: transformFlash,
                        rechargePulse: rechargePulse
                    )
                    .scaleEffect(coreScale)
                    .contentShape(Circle())
                    .onTapGesture { handleOmnitrixTap() }

                    Text(stateLabel)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1.25)
                        .foregroundStyle(coreColor)
                        .shadow(color: coreColor.opacity(0.7), radius: 4)
                        .lineLimit(1)

                    Text(selectedAlien.name)
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(controller.ledaState == .idle ? 0.35 : 0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            if transformFlash {
                Circle()
                    .fill(.white)
                    .frame(width: 185, height: 185)
                    .scaleEffect(coreScale > 1.2 ? 1.12 : 0.5)
                    .opacity(coreScale > 1.2 ? 0.92 : 0.18)
                    .blur(radius: coreScale > 1.2 ? 1 : 8)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.22), value: coreScale)
            }

            if controller.socketState == .connecting {
                ProgressView()
                    .controlSize(.mini)
                    .tint(activeGreen)
                    .offset(y: 78)
            } else if controller.socketState == .failed {
                statusError("BRIDGE OFFLINE")
            } else if controller.errorMessage != nil {
                statusError("LEDA ERROR")
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                energyPulse = true
            }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                ringSpin = true
            }
        }
    }

    private func statusError(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(rechargeRed)
            .tracking(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.78), in: Capsule())
            .overlay(Capsule().stroke(rechargeRed.opacity(0.5), lineWidth: 1))
            .offset(y: 79)
    }
}

private struct OmnitrixCoreView: View {
    let visualMode: OmnitrixVisualMode
    let accent: Color
    let activeGreen: Color
    let deepGreen: Color
    let rechargeRed: Color
    let selectedAlien: ClassicAlien
    let ledaState: LedaState
    let dialRotation: Double
    let ringSpin: Bool
    let transformFlash: Bool
    let rechargePulse: Bool

    private var isActive: Bool {
        visualMode == .active || visualMode == .transforming
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: 158, height: 158)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: accent.opacity(0.35), radius: 14)

            Circle()
                .trim(from: 0.035, to: 0.215)
                .stroke(accent.opacity(0.92), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 148, height: 148)
                .rotationEffect(.degrees(ringSpin ? 360 : 0))

            Circle()
                .trim(from: 0.535, to: 0.715)
                .stroke(accent.opacity(0.92), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 148, height: 148)
                .rotationEffect(.degrees(ringSpin ? -360 : 0))

            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.72) : accent.opacity(0.78))
                    .frame(width: 8, height: 28)
                    .offset(y: -72)
                    .rotationEffect(.degrees(Double(index) * 90 + 45))
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(visualMode == .recharge ? 0.95 : 0.88),
                            accent.opacity(0.34),
                            deepGreen.opacity(0.28),
                            .black
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 72
                    )
                )
                .frame(width: 132, height: 132)
                .overlay {
                    Circle().stroke(accent.opacity(0.62), lineWidth: 3)
                }
                .scaleEffect(visualMode == .recharge && rechargePulse ? 1.05 : 1.0)

            Circle()
                .stroke(Color.black.opacity(0.75), lineWidth: 8)
                .frame(width: 108, height: 108)

            Group {
                if visualMode == .ready || visualMode == .recharge {
                    HourglassShape()
                        .fill(Color.black)
                        .overlay {
                            HourglassShape()
                                .stroke(visualMode == .recharge ? rechargeRed.opacity(0.5) : activeGreen.opacity(0.22), lineWidth: 1.5)
                        }
                        .frame(width: 72, height: 82)
                        .shadow(color: accent.opacity(0.95), radius: visualMode == .recharge ? 10 : 6)
                } else {
                    ZStack {
                        DiamondShape()
                            .fill(Color.black.opacity(0.92))
                            .frame(width: 88, height: 108)
                            .rotationEffect(.degrees(dialRotation))

                        Image(selectedAlien.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 94, height: 108)
                            .shadow(color: activeGreen.opacity(0.8), radius: 5)
                    }
                }
            }

            if isActive {
                Circle()
                    .stroke(activeGreen.opacity(0.34), lineWidth: 2)
                    .frame(width: 118, height: 118)
                    .scaleEffect(ledaState == .speaking ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.42), value: ledaState)
            }

            if transformFlash {
                HourglassShape()
                    .fill(Color.white)
                    .frame(width: 80, height: 90)
                    .shadow(color: .white, radius: 18)
            }
        }
    }
}

private struct OmnitrixBackdrop: View {
    let color: Color
    let energized: Bool
    let pulse: Bool

    var body: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [
                    color.opacity(energized ? (pulse ? 0.23 : 0.12) : 0.05),
                    Color.black.opacity(0.95)
                ],
                center: .center,
                startRadius: 12,
                endRadius: 120
            )

            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 3) ? Color.white.opacity(0.12) : color.opacity(0.18))
                    .frame(width: CGFloat(2 + index % 3), height: CGFloat(2 + index % 3))
                    .offset(
                        x: CGFloat((index * 37) % 150) - 75,
                        y: CGFloat((index * 61) % 170) - 85
                    )
                    .scaleEffect(pulse ? 1.25 : 0.72)
                    .opacity(energized ? 1 : 0.35)
            }
        }
    }
}

struct AlienSelectorView: View {
    @Binding var selectedIndex: Int
    let accent: Color
    let onDial: () -> Void
    let onSelect: (Int) -> Void

    @State private var crownPosition = 0.0
    @State private var scanOffset: CGFloat = -46
    @State private var selectorPulse = false
    @FocusState private var isCrownFocused: Bool

    private var selectedAlien: ClassicAlien {
        ClassicAlien.originalTen[selectedIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: accent, radius: 4)

                Text("DNA SELECT")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                    .tracking(1.45)
            }

            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 158, height: 158)
                    .overlay(Circle().stroke(accent.opacity(0.22), lineWidth: 1))

                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [accent, .black, accent.opacity(0.35), .white.opacity(0.7), accent, .black, accent],
                            center: .center
                        ),
                        lineWidth: 8
                    )
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(Double(-selectedIndex) * 36))
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: selectedIndex)

                ForEach(0..<ClassicAlien.originalTen.count, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIndex ? Color.white : accent.opacity(0.44))
                        .frame(width: index == selectedIndex ? 4 : 2, height: index == selectedIndex ? 16 : 9)
                        .offset(y: -73)
                        .rotationEffect(.degrees(Double(index) * 36))
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(selectorPulse ? 0.78 : 0.52), accent.opacity(0.18), .black],
                            center: .center,
                            startRadius: 8,
                            endRadius: 68
                        )
                    )
                    .frame(width: 128, height: 128)

                DiamondShape()
                    .fill(Color.black.opacity(0.91))
                    .frame(width: 88, height: 110)

                Image(selectedAlien.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 112)
                    .id(selectedAlien.id)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.62).combined(with: .opacity),
                            removal: .scale(scale: 1.28).combined(with: .opacity)
                        )
                    )
                    .shadow(color: accent.opacity(0.88), radius: 7)

                Rectangle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 92, height: 1.5)
                    .shadow(color: accent, radius: 3)
                    .offset(y: scanOffset)
                    .mask(Circle().frame(width: 114, height: 114))

                HStack {
                    Image(systemName: "chevron.left")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(accent.opacity(0.82))
                .frame(width: 168)
            }

            Text(selectedAlien.name)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(color: accent.opacity(0.55), radius: 4)

            Text("CROWN TO SCAN  •  TAP TO LOCK")
                .font(.system(size: 6.5, weight: .bold, design: .rounded))
                .foregroundStyle(accent.opacity(0.72))
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

            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                selectedIndex = newIndex
            }
            onDial()
        }
        .onTapGesture { onSelect(selectedIndex) }
        .onAppear {
            crownPosition = Double(selectedIndex)
            isCrownFocused = true

            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                scanOffset = 46
                selectorPulse = true
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
