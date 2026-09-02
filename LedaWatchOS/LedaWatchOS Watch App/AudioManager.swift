import Foundation
import AVFoundation

final class AudioManager {

    private let audioEngine = AVAudioEngine()
    private var didSendAudioFormat = false

    private(set) var isRecording = false

    var onFormat: ((AVAudioFormat) -> Void)?
    var onAudioData: ((Data) -> Void)?
    var onFailure: ((Error) -> Void)?

    func start() {
        guard !isRecording else {
            return
        }

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
            ) { [weak self] buffer, _ in
                guard let self else {
                    return
                }

                if !self.didSendAudioFormat {
                    self.onFormat?(buffer.format)
                    self.didSendAudioFormat = true
                }

                guard let data = self.makeData(from: buffer) else {
                    return
                }

                self.onAudioData?(data)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            print("LEDA microphone LIVE")
        } catch {
            print("Audio error:", error)
            onFailure?(error)
        }
    }

    func stop() {
        guard isRecording else {
            print("LEDA microphone was not running")
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        isRecording = false
        didSendAudioFormat = false

        print("LEDA microphone OFF")
    }

    private func makeData(from buffer: AVAudioPCMBuffer) -> Data? {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers

        guard let rawData = audioBuffer.mData else {
            return nil
        }

        return Data(
            bytes: rawData,
            count: Int(audioBuffer.mDataByteSize)
        )
    }
}
