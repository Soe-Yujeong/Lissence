import SwiftUI
import AVFoundation

struct DetectionDetailView: View {
    @Binding var currentPath: String
    @State private var isVoiceOn = false

    // 호출 감지 팝업
    @State private var showCallAlert = false
    @State private var detectedKeyword = ""

    // 매니저 연결
    @StateObject var connectivity = ConnectivityManager.shared
    @StateObject var soundDetector = SoundDetector()
    @StateObject var speechManager = SpeechManager()
    @StateObject var keywordManager = KeywordManager()

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. 헤더 영역 (상단 네비게이션 및 설정)
            headerView
            
            Spacer()
            
            // MARK: - 2. 컨텐츠 영역 (메인 로직 및 정보 표시)
            contentView
            
            Spacer()
            
            // MARK: - 3. 하단 컨트롤 영역 (버튼 및 인터랙션)
            bottomControls
        }
        // 호출 감지 팝업
        .alert("누군가 부르는 것 같아요", isPresented: $showCallAlert) {
            Button("음성인식 켜기") { isVoiceOn = true }
            Button("무시", role: .cancel) { }
        } message: {
            Text("'\(detectedKeyword)' 소리가 감지됐어요. 음성인식으로 전환할까요?")
        }
        // 화면이 나타날 때 소리 감지 시작 + 콜백 연결
        .onAppear {
            soundDetector.startDetection()

            // 아이폰 speech 감지 → 롤링 버퍼 → 키워드 분석
            soundDetector.onSpeechDetected = { [weak speechManager] buffer in
                guard let speechManager else { return }
                speechManager.analyzeBuffer(buffer, keywords: keywordManager.keywords) { matched in
                    detectedKeyword = matched
                    showCallAlert = true
                    // 워치에도 결과 전송
                    let msg = MessageData(
                        title: "'\(matched)' 감지됨",
                        iconName: "person.wave.2.fill",
                        isDanger: false
                    )
                    connectivity.send(message: msg)
                }
            }

            // 워치 오디오 수신 → 키워드 분석 → 워치로 결과 전송
            connectivity.onAudioDataReceived = { [weak speechManager] data in
                print("📥 [1] 워치 오디오 수신: \(data.count / 1024)KB")
                guard let speechManager else { print("❌ speechManager nil"); return }
                if let buffer = Self.dataToBuffer(data) {
                    print("✅ [2] 버퍼 변환 성공: \(buffer.frameLength) frames")
                    print("🔑 [3] 키워드 목록: \(keywordManager.keywords)")
                    speechManager.analyzeBuffer(buffer, keywords: keywordManager.keywords) { matched in
                        print("✅ [4] 키워드 매칭: \(matched)")
                        detectedKeyword = matched
                        showCallAlert = true
                        // 워치에도 결과 전송
                        let msg = MessageData(
                            title: "'\(matched)' 감지됨",
                            iconName: "person.wave.2.fill",
                            isDanger: false
                        )
                        connectivity.send(message: msg)
                        print("📤 [5] 워치로 메시지 전송")
                    }
                } else {
                    print("❌ [2] 버퍼 변환 실패")
                }
            }
        }
        .onDisappear {
            soundDetector.stopDetection()
            // 화면을 벗어나면 음성인식도 확실히 끄기
            if isVoiceOn {
                speechManager.stopRecording()
                isVoiceOn = false
            }
        }
        // 토글 버튼이 눌릴 때마다 음성 인식 켜고 끄기
        .onChange(of: isVoiceOn) { _, newValue in
            if newValue {
                soundDetector.stopDetection()  // 마이크 충돌 방지
                speechManager.startRecording()
            } else {
                speechManager.stopRecording()
                soundDetector.startDetection() // 감지 모드 재시작
            }
        }
        // 자막창 (Sheet)
        .sheet(isPresented: $isVoiceOn) {
            // 더미 텍스트 대신 speechManager의 실제 텍스트를 전달합니다.
            let displayText = speechManager.transcript.isEmpty ? "말씀을 시작해주세요..." : speechManager.transcript
            
            SubtitleWidgetView(isShowing: $isVoiceOn, text: displayText)
                .interactiveDismissDisabled()
        }
    }
}

// MARK: - Subviews (섹션별로 나누어 관리)
extension DetectionDetailView {
    
    // Header: 홈 버튼과 음성인식 토글
    private var headerView: some View {
        HStack {
            Button(action: { currentPath = "home" }) {
                Image(systemName: "house.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Toggle("음성인식", isOn: $isVoiceOn)
                .toggleStyle(.button)
                .tint(.orange)
        }
        .padding(.horizontal)
        .frame(height: 60)
        .overlay {
            Text("감지 모드")
                .font(.system(size: 40, weight: .bold))
                .offset(y: 130)
        }
    }
    
    // Content: 소리 분석 상태 표시
    private var contentView: some View {
        VStack(spacing: 20) {
            // ★ 워치에서 감지되어 전송된 소리 (Watch → iPhone)
            if let watchMessage = connectivity.receivedMessage {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "applewatch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("워치에서 감지됨")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: watchMessage.iconName)
                        .font(.system(size: 70))
                        .foregroundColor(watchMessage.isDanger ? .red : .green)

                    Text(watchMessage.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(watchMessage.isDanger ? .red : .green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.bottom, soundDetector.lastDetectedSound.isEmpty ? 0 : 8)
            }

            // ★ 아이폰에서 직접 감지된 소리 (iPhone 마이크)
            if soundDetector.lastDetectedSound.isEmpty && connectivity.receivedMessage == nil {
                // 아무것도 감지되지 않은 기본 화면
                Image(systemName: "waveform")
                    .font(.system(size: 90))
                    .foregroundColor(.blue)

                Text("소리 분석 중..")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            } else if !soundDetector.lastDetectedSound.isEmpty {
                VStack(spacing: 8) {
                    if connectivity.receivedMessage != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "iphone")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("아이폰에서 감지됨")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Image(systemName: getIconForSound(soundDetector.lastDetectedSound))
                        .font(.system(size: connectivity.receivedMessage != nil ? 60 : 90))
                        .foregroundColor(.red)

                    Text(soundDetector.lastDetectedSound)
                        .font(connectivity.receivedMessage != nil ? .title2 : .title)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }
    
    // Bottom Controls: 모드 전환 버튼 및 워치 전송 테스트
    private var bottomControls: some View {
        VStack(spacing: 15) {
            // 워치 전송 테스트 버튼
            Button("워치로 위험 신호 보내기") {
                let msg = MessageData(title: "위험 감지됨!", iconName: "exclamationmark.triangle", isDanger: true)
                connectivity.send(message: msg)
            }
            .padding(.bottom, 10)
            
            // 음악 모드 전환 버튼
            Button(action: { currentPath = "music" }) {
                Label("음악모드 전환", systemImage: "music.quarternote.3")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(15)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }
    
    // 워치에서 받은 Data → AVAudioPCMBuffer 변환 (16kHz 모노 float32)
    static func dataToBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else { return nil }

        // 워치에서 Int16으로 압축해서 보내므로 Float32로 변환
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { ptr in
            guard let src = ptr.baseAddress?.assumingMemoryBound(to: Int16.self),
                  let dst = buffer.floatChannelData else { return }
            for i in 0..<Int(frameCount) {
                dst[0][i] = Float(src[i]) / 32767.0
            }
        }
        return buffer
    }

    // 감지된 텍스트에 따라 알맞은 아이콘을 반환하는 헬퍼 함수
    private func getIconForSound(_ sound: String) -> String {
        if sound.contains("경적") {
            return "car.fill"
        } else if sound.contains("위험 신호") {
            return "bell.and.waves.left.and.right.fill"
        } else if sound.contains("큰 소음") || sound.contains("외침") {
            return "exclamationmark.bubble.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }
}





