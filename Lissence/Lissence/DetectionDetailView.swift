import SwiftUI

struct DetectionDetailView: View {
    @Binding var currentPath: String
    @State private var isVoiceOn = false
    
    // 매니저 연결 (이전에 테스트했던 클래스들을 가져옵니다)
    @StateObject var connectivity = ConnectivityManager.shared
    @StateObject var soundDetector = SoundDetector()
    @StateObject var speechManager = SpeechManager()

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
        // 화면이 나타날 때 소리 감지 시작, 사라질 때 중지
        .onAppear {
            soundDetector.startDetection()
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
        .onChange(of: isVoiceOn) { newValue in
            if newValue {
                speechManager.startRecording()
            } else {
                speechManager.stopRecording()
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
        VStack(spacing: 25) {
            // 감지된 소리가 없을 때 (기본 화면)
            if soundDetector.lastDetectedSound.isEmpty {
                Image(systemName: "waveform")
                    .font(.system(size: 90))
                    .foregroundColor(.blue)
                
                Text("소리 분석 중..")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            } else {
                // 위험 소리가 감지되었을 때
                Image(systemName: getIconForSound(soundDetector.lastDetectedSound))
                    .font(.system(size: 90))
                    .foregroundColor(.red)
                
                Text(soundDetector.lastDetectedSound)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
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





