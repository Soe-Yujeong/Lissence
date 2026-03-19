/// 감지 모드(소리 분류)
/// - 애플의 SoundAnalysis를 사용하여 감지모드에서 소리의 종류를 인식합니다.

import Foundation
import SoundAnalysis
import AVFoundation
import Combine

class SoundDetector: NSObject, SNResultsObserving, ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.Lissence.AnalysisQueue")

    // UI에서 현재 어떤 소리가 들리는지 보여줄 변수
    @Published var statusText: String = "주변 소리 분석 중..."
    @Published var lastDetectedSound: String = ""
    @Published var isDetecting: Bool = false

    // MARK: - 롤링 버퍼 (최근 2초 오디오 저장)
    private var rollingBuffers: [AVAudioPCMBuffer] = []
    private var rollingBufferDuration: Double = 0
    private let maxBufferDuration: Double = 2.0
    private let rollingBufferQueue = DispatchQueue(label: "com.Lissence.RollingBufferQueue")

    // speech 감지 시 버퍼를 전달하는 콜백
    var onSpeechDetected: ((AVAudioPCMBuffer) -> Void)?

    // 연속 트리거 방지 (최소 3초 간격)
    private var lastSpeechSentTime: Date = .distantPast

    func startDetection() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 모드를 .default 또는 .videoRecording 등으로 변경하여 더 넓은 대역폭 확보
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("오디오 세션 설정 실패")
        }

        // 2. 분석기(Analyzer) 설정
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        analyzer = SNAudioStreamAnalyzer(format: recordingFormat)
        
        do {
            // 3. Apple 제공 시스템 분류기 설정 (.version1 사용)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer?.add(request, withObserver: self)
            
            // 4. 마이크 입력을 분석기로 전달 (Tap 설치)
            inputNode.installTap(onBus: 0, bufferSize: 8000, format: recordingFormat) { [weak self] buffer, time in
                // 롤링 버퍼에 저장
                self?.appendToRollingBuffer(buffer)
                // 소리 분석
                self?.analysisQueue.async {
                    self?.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }
            
            try audioEngine.start()
            DispatchQueue.main.async { self.isDetecting = true }
        } catch {
            print("감지 시작 실패: \(error)")
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
        
        // 임계값을 0.5로 낮추어 더 민감하게 반응하게 함
        if bestClassification.confidence > 0.5 {
            let soundLabel = bestClassification.identifier
            print("감지된 소리: \(soundLabel), 신뢰도: \(bestClassification.confidence)") // 디버깅용 출력
            
            DispatchQueue.main.async {
                self.processResult(label: soundLabel)
            }
        }
    }
    private func processResult(label: String) {
        switch label {
        // 사이렌 관련 레이블 통합
        case "siren", "emergency_vehicle", "fire_alarm":
            sendDangerAlert(title: "위험 신호 감지!", icon: "bell.and.waves.left.and.right.fill")

        // 경적 관련
        case "car_horn", "vehicle_horn":
            sendDangerAlert(title: "경적 감지!", icon: "car.fill")

        // 외침 관련 레이블 통합
        case "shouting", "screaming", "yelling", "laughter":
            sendDangerAlert(title: "큰 소음/외침 감지!", icon: "exclamationmark.bubble.fill")

        // 사람 음성 감지 → UI 알림 없이 롤링 버퍼만 전달 (3초 간격 제한)
        case "speech", "conversation", "narration", "monologue":
            guard Date().timeIntervalSince(lastSpeechSentTime) > 3.0 else { break }
            if let combined = extractCombinedBuffer() {
                lastSpeechSentTime = Date()
                onSpeechDetected?(combined)
            }

        default:
            break
        }
    }

    // MARK: - 롤링 버퍼 관리
    private func appendToRollingBuffer(_ buffer: AVAudioPCMBuffer) {
        // 탭 버퍼는 재사용되므로 반드시 복사해서 저장
        guard let copy = copyBuffer(buffer) else { return }

        rollingBufferQueue.async { [weak self] in
            guard let self else { return }
            let duration = Double(copy.frameLength) / copy.format.sampleRate
            self.rollingBuffers.append(copy)
            self.rollingBufferDuration += duration

            // 2초 초과분 제거
            while self.rollingBufferDuration > self.maxBufferDuration,
                  let first = self.rollingBuffers.first {
                let firstDuration = Double(first.frameLength) / first.format.sampleRate
                self.rollingBuffers.removeFirst()
                self.rollingBufferDuration -= firstDuration
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
            guard let dst = combined.floatChannelData,
                  let src = buffer.floatChannelData else { continue }
            for ch in 0..<Int(format.channelCount) {
                memcpy(dst[ch] + Int(offset), src[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
            offset += buffer.frameLength
        }
        return combined
    }

    private func sendDangerAlert(title: String, icon: String) {
        self.lastDetectedSound = title
        
        // 워치로 데이터 전송 (ConnectivityManager 사용)
        let msg = MessageData(title: title, iconName: icon, isDanger: true)
        ConnectivityManager.shared.send(message: msg)
        
        print("위험 감지 및 전송: \(title)")
    }
}

