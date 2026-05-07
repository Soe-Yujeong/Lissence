import SoundAnalysis
import WatchKit
import Foundation
import Combine
import AVFoundation
import CoreMedia

// 감지할 소리 타입
enum DangerSound {
    case siren       // 사이렌
    case carHorn     // 차량 경적
    case speech      // 사람 음성
    case unknown
}

class SoundClassifier: NSObject, ObservableObject {

    private var audioEngine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private let analysisQueue = DispatchQueue(label: "SoundAnalysisQueue")
    private var extendedSession: WKExtendedRuntimeSession?

    @Published var isRunning = false
    @Published var detectedSound: DangerSound = .unknown
    @Published var confidence: Double = 0

    var onDangerDetected: ((DangerSound, Double) -> Void)?

    // 신뢰도 임계값 (이 이상일 때만 반응)
    var confidenceThreshold: Double = 0.6

    // MARK: - 시작
    func start() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted else {
                print("마이크 권한 거부됨")
                return
            }
            DispatchQueue.main.async {
                // Extended Runtime Session 시작 (watchOS 백그라운드 유지)
                self?.extendedSession = WKExtendedRuntimeSession()
                self?.extendedSession?.start()
                self?.startEngine()
            }
        }
    }

    private func startEngine() {
        audioEngine = AVAudioEngine() // 매번 새로 생성해서 탭 중복 방지
        do {
            print("1️⃣ 오디오 세션 설정 시작")
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record)
            try session.setActive(true)
            print("2️⃣ 오디오 세션 활성화 완료")

            // SoundAnalysis 요청 생성 (애플 내장 모델)
            request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request?.windowDuration = CMTimeMakeWithSeconds(1.5, preferredTimescale: 44100)
            request?.overlapFactor = 0.5
            print("3️⃣ SoundAnalysis 요청 생성 완료")

            // 오디오 엔진 설정 (watchOS는 inputFormat 사용)
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            print("4️⃣ 오디오 포맷: \(inputFormat.sampleRate)Hz, 채널: \(inputFormat.channelCount)")
            guard inputFormat.sampleRate > 0 else {
                print("❌ 유효하지 않은 오디오 포맷")
                return
            }
            analyzer = SNAudioStreamAnalyzer(format: inputFormat)

            try analyzer?.add(request!, withObserver: self)

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
                self?.analysisQueue.async {
                    self?.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }

            try audioEngine.start()
            DispatchQueue.main.async { self.isRunning = true }

        } catch {
            print("❌ SoundClassifier 오류: \(error)")
            print("❌ 오류 상세: \(error.localizedDescription)")
        }
    }

    // MARK: - 중지
    func stop() {
        extendedSession?.invalidate()
        extendedSession = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        analyzer?.removeAllRequests()
        try? AVAudioSession.sharedInstance().setActive(false)

        DispatchQueue.main.async {
            self.isRunning = false
            self.detectedSound = .unknown
            self.confidence = 0
        }
    }

    // MARK: - 소리 타입 매핑
    private func mapToSoundType(_ identifier: String) -> DangerSound? {
        switch identifier {
        case let id where id.contains("siren"):
            return .siren
        case let id where id.contains("car_horn") || id.contains("horn"):
            return .carHorn
        case let id where id.contains("speech"), let id where id.contains("shout"):
            return .speech
        default:
            return nil
        }
    }
}

// MARK: - SNResultsObserving
extension SoundClassifier: SNResultsObserving {

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }

        // 신뢰도 높은 순으로 정렬
        let sorted = result.classifications.sorted { $0.confidence > $1.confidence }

        for classification in sorted {
            guard classification.confidence >= confidenceThreshold else { break }
            guard let soundType = mapToSoundType(classification.identifier) else { continue }

            DispatchQueue.main.async { [weak self] in
                self?.detectedSound = soundType
                self?.confidence = classification.confidence
                self?.onDangerDetected?(soundType, classification.confidence)
            }
            return
        }

        // 아무것도 감지 못했을 때
        DispatchQueue.main.async { [weak self] in
            self?.detectedSound = .unknown
            self?.confidence = 0
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("분류 오류: \(error)")
    }
}
