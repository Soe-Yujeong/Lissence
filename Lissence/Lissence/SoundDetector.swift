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

//    func startDetection() {
//        // 1. 오디오 세션 설정
//        let audioSession = AVAudioSession.sharedInstance()
//        do {
//            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
//            try audioSession.setActive(true)
//        } catch {
//            print("오디오 세션 설정 실패")
//        }
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
            sendDangerAlert(title: "🚨 위험 신호 감지!", icon: "bell.and.waves.left.and.right.fill")
            
        // 경적 관련
        case "car_horn", "vehicle_horn":
            sendDangerAlert(title: "🚘 경적 감지!", icon: "car.fill")
            
        // 외침 관련 레이블 통합 (shouting, screaming, yelling 등)
        case "shouting", "screaming", "yelling", "laughter": // 웃음소리가 외침으로 인식될 때가 많음
            sendDangerAlert(title: "🗣️ 큰 소음/외침 감지!", icon: "exclamationmark.bubble.fill")
            
        default:
            break
        }
    }

    private func sendDangerAlert(title: String, icon: String) {
        self.lastDetectedSound = title
        
        // 워치로 데이터 전송 (ConnectivityManager 사용)
        let msg = MessageData(title: title, iconName: icon, isDanger: true)
        ConnectivityManager.shared.send(message: msg)
        
        print("위험 감지 및 전송: \(title)")
    }
}

