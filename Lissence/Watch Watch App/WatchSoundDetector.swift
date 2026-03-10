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

    // UI에서 현재 어떤 소리가 들리는지 보여줄 변수
    @Published var lastDetectedSound: String = ""
    @Published var isDetecting: Bool = false

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

        default:
            break
        }
    }

    private func sendDangerAlert(title: String, icon: String) {
        self.lastDetectedSound = title

        // 아이폰으로 데이터 전송 (ConnectivityManager 사용)
        let msg = MessageData(title: title, iconName: icon, isDanger: true)
        ConnectivityManager.shared.send(message: msg)

        print("워치 위험 감지 및 아이폰으로 전송: \(title)")
    }
}
