import Foundation
import AVFoundation

final class RealtimeAudioPlayer {

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private let streamFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!

    private var isPrepared = false

    func play(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        do {
            try prepareIfNeeded()
        } catch {
            print("Realtime playback setup failed:", error)
            return
        }

        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: streamFormat,
                frameCapacity: frameCount
              ) else {
            return
        }

        buffer.frameLength = frameCount

        guard let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData else {
            return
        }

        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.baseAddress else {
                return
            }

            memcpy(destination, source, data.count)
        }

        playerNode.scheduleBuffer(buffer)

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func clear() {
        playerNode.stop()

        if audioEngine.isRunning {
            playerNode.play()
        }
    }

    func stop() {
        playerNode.stop()
        audioEngine.stop()
        isPrepared = false
    }

    private func prepareIfNeeded() throws {
        guard !isPrepared else {
            return
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat)
        try session.setActive(true)

        audioEngine.attach(playerNode)
        audioEngine.connect(
            playerNode,
            to: audioEngine.mainMixerNode,
            format: streamFormat
        )

        audioEngine.prepare()
        try audioEngine.start()
        playerNode.play()

        isPrepared = true
    }
}
