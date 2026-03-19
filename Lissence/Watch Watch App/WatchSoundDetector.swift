/// 워치 감지 모드(소리 분류)
/// - 애플의 SoundAnalysis를 사용하여 워치에서 소리의 종류를 인식하고, 아이폰으로 전송합니다.

import Foundation
import SoundAnalysis
import AVFoundation
import Combine

class WatchSoundDetector: NSObject, SNResultsObserving, ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.Lissence.WatchAnalysisQueue")

    @Published var lastDetectedSound: String = ""
    @Published var isDetecting: Bool = false

    // MARK: - 롤링 버퍼
    private var rollingBuffers: [AVAudioPCMBuffer] = []
    private var rollingBufferDuration: Double = 0
    private let maxBufferDuration: Double = 2.0
    private let rollingBufferQueue = DispatchQueue(label: "com.Lissence.WatchRollingBufferQueue")

    // 연속 전송 방지 (최소 3초 간격)
    private var lastSentTime: Date = .distantPast

    func startDetection() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("워치 오디오 세션 설정 실패: \(error)")
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        analyzer = SNAudioStreamAnalyzer(format: recordingFormat)

        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer?.add(request, withObserver: self)

            inputNode.installTap(onBus: 0, bufferSize: 8000, format: recordingFormat) { [weak self] buffer, time in
                self?.appendToRollingBuffer(buffer)
                self?.analysisQueue.async {
                    self?.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }

            try audioEngine.start()
            DispatchQueue.main.async { self.isDetecting = true }
        } catch {
            print("워치 감지 시작 실패: \(error)")
        }
    }

    func stopDetection() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        analyzer = nil
        isDetecting = false
    }

    // ★ 소리가 분석될 때마다 실행되는 함수
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult,
              let bestClassification = classificationResult.classifications.first else { return }

        if bestClassification.confidence > 0.5 {
            let soundLabel = bestClassification.identifier
            print("워치 감지된 소리: \(soundLabel), 신뢰도: \(bestClassification.confidence)")

            DispatchQueue.main.async {
                self.processResult(label: soundLabel)
            }
        }
    }

    private func processResult(label: String) {
        switch label {
        case "siren", "emergency_vehicle", "fire_alarm":
            sendDangerAlert(title: "위험 신호 감지!", icon: "bell.and.waves.left.and.right.fill")

        case "car_horn", "vehicle_horn":
            sendDangerAlert(title: "경적 감지!", icon: "car.fill")

        case "shouting", "screaming", "yelling", "laughter":
            sendDangerAlert(title: "큰 소음/외침 감지!", icon: "exclamationmark.bubble.fill")

        // 사람 음성 감지 → 버퍼 추출 후 아이폰으로 전송
        case "speech", "conversation", "narration", "monologue":
            sendAudioToPhone()

        default:
            break
        }
    }

    // MARK: - 롤링 버퍼 관리
    private func appendToRollingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let copy = copyBuffer(buffer) else { return }
        rollingBufferQueue.async { [weak self] in
            guard let self else { return }
            let duration = Double(copy.frameLength) / copy.format.sampleRate
            self.rollingBuffers.append(copy)
            self.rollingBufferDuration += duration
            while self.rollingBufferDuration > self.maxBufferDuration,
                  let first = self.rollingBuffers.first {
                self.rollingBuffers.removeFirst()
                self.rollingBufferDuration -= Double(first.frameLength) / first.format.sampleRate
            }
        }
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        guard let src = buffer.floatChannelData, let dst = copy.floatChannelData else { return nil }
        for ch in 0..<Int(buffer.format.channelCount) {
            memcpy(dst[ch], src[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
        }
        return copy
    }

    private func extractCombinedBuffer() -> AVAudioPCMBuffer? {
        var buffers: [AVAudioPCMBuffer] = []
        rollingBufferQueue.sync { buffers = self.rollingBuffers }
        guard !buffers.isEmpty, let format = buffers.first?.format else { return nil }
        let totalFrames = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard let combined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
        combined.frameLength = totalFrames
        var offset = AVAudioFrameCount(0)
        for buffer in buffers {
            guard let dst = combined.floatChannelData, let src = buffer.floatChannelData else { continue }
            for ch in 0..<Int(format.channelCount) {
                memcpy(dst[ch] + Int(offset), src[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
            offset += buffer.frameLength
        }
        return combined
    }

    // MARK: - 16kHz 모노로 다운샘플링 후 아이폰 전송
    private func sendAudioToPhone() {
        // 최소 3초 간격으로만 전송
        guard Date().timeIntervalSince(lastSentTime) > 3.0 else { return }
        guard let combined = extractCombinedBuffer() else { return }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else { return }

        guard let converter = AVAudioConverter(from: combined.format, to: targetFormat) else { return }

        let outputFrameCapacity = AVAudioFrameCount(targetFormat.sampleRate * maxBufferDuration)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return }

        var inputConsumed = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return combined
        }

        guard status != .error,
              let floatData = outputBuffer.floatChannelData else { return }

        let frameCount = Int(outputBuffer.frameLength)

        // Float32 → Int16 변환 (크기 절반으로 줄임: 128KB → 64KB)
        var int16Samples = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let clamped = max(-1.0, min(1.0, floatData[0][i]))
            int16Samples[i] = Int16(clamped * 32767)
        }
        let data = int16Samples.withUnsafeBytes { Data($0) }

        lastSentTime = Date()
        ConnectivityManager.shared.sendAudioData(data)
        print("워치 → 아이폰 오디오 전송: \(data.count / 1024)KB")
    }

    private func sendDangerAlert(title: String, icon: String) {
        self.lastDetectedSound = title
        let msg = MessageData(title: title, iconName: icon, isDanger: true)
        ConnectivityManager.shared.send(message: msg)
        print("워치 위험 감지 및 아이폰으로 전송: \(title)")
    }
}
