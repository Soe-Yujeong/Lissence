/// 음성인식기능(in 감지모드)
/// - 애플의 Speech와 SoundAnalysis를 이용하여 음성인식을 수행합니다.

import Foundation
import Speech
import AVFoundation
import Combine

// NSObject를 상속받아야 음성 인식 델리게이트를 사용할 수 있습니다.
class SpeechManager: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var transcript: String = ""
    @Published var isRecording: Bool = false

    // 권한 캐싱 (매번 요청 방지)
    private var isAuthorized = false
    // 중복 분석 방지
    private var isAnalyzing = false

    override init() {
        super.init()
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            self?.isAuthorized = (status == .authorized)
        }
    }

    func startRecording() {
        // 기존 작업이 있다면 취소
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        // 오디오 세션 설정 (말소리 듣기 모드)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("오디오 세션 설정 실패")
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true // 말하는 도중에도 결과 보여주기

        // 음성 인식 시작
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                // 실시간으로 변환된 텍스트를 transcript에 저장
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                    
                    // 만약 특정 단어가 포함되어 있다면? (감지 모드 테스트)
                    if self.transcript.contains("도와줘") {
                        print("위험 키워드 감지!")
                        // 여기서 ConnectivityManager.shared.send(...)를 호출하면 워치로 갑니다.
                    }
                }
            }

            if error != nil || result?.isFinal == true {
                self.stopRecording()
            }
        }

        // 마이크 입력 연결
        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            print("오디오 엔진 시작 실패")
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRecording = false
    }

    // MARK: - 버퍼 기반 키워드 분석 (오디오 엔진 없이 처리)
    func analyzeBuffer(_ buffer: AVAudioPCMBuffer, keywords: [String], onMatch: @escaping (String) -> Void) {
        guard !isAnalyzing else { print("⏭️ analyzeBuffer 스킵 (이미 분석 중)"); return }
        guard isAuthorized else { print("❌ 음성인식 권한 없음"); return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { print("❌ recognizer 없음 또는 불가"); return }
        print("🔍 analyzeBuffer 시작")

        isAnalyzing = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.append(buffer)
        request.endAudio()

        recognizer.recognitionTask(with: request) { [weak self] result, error in
            defer { DispatchQueue.main.async { self?.isAnalyzing = false } }
            if let error { print("버퍼 인식 오류: \(error)"); return }
            guard let result = result, result.isFinal else { return }
            let text = result.bestTranscription.formattedString
            print("버퍼 인식 결과: \(text)")

            for keyword in keywords {
                if text.contains(keyword) {
                    DispatchQueue.main.async { onMatch(keyword) }
                    return
                }
            }
        }
    }
}

