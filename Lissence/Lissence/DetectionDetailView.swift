/// 감지모드입니다.
/// - 기능
///     - 위험 소리 분류 및 출력
///     - 사람의 말소리 실시간 출력

import SwiftUI

struct DetectionDetailView: View {
    @Binding var currentPath: String
    @State private var isVoiceOn = false
    
    // [추가] 감지 결과 표시 후 대기 상태로 돌아가기 위한 타이머
    @State private var resetTimer: Timer?
    
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
            // 화면 나갈때 타이머 취소
            resetTimer?.invalidate()
            // 화면을 벗어나면 음성인식도 확실히 끄기
            if isVoiceOn { speechManager.stopRecording(); isVoiceOn = false }
        }
        // 토글 버튼이 눌릴 때마다 음성 인식 켜고 끄기
        .onChange(of: isVoiceOn) { newValue in
            if newValue {
                speechManager.startRecording()
            } else {
                speechManager.stopRecording()
            }
        }
        // [추가] 소리가 감지되었을 때 자동으로 대기 상태로 돌아가는 로직
        .onChange(of: soundDetector.lastDetectedSound) { newValue in
            if !newValue.isEmpty {
                // 새로운 소리가 감지되면 기존 타이머 리셋
                resetTimer?.invalidate()
                
                // 4초 후 lastDetectedSound를 빈 문자열로 만들어 대기 화면으로 되돌림
                resetTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
                    soundDetector.lastDetectedSound = ""
                }
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
        VStack(spacing: 30) {
            if soundDetector.lastDetectedSound.isEmpty {
                // [수정] 감지 중일 때: 위치와 같은 ProgressView 적용
                VStack(spacing: 25) {
                    // ProgressView 크게(아이폰)
                    ProgressView()
                        .scaleEffect(2.0)
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    Text("주변 소리 분석 중...")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .transition(.opacity)
            } else {
                // 소리 감지 시: 결과 출력
                VStack(spacing: 20) {
                    Image(systemName: getIconForSound(soundDetector.lastDetectedSound))
                        .font(.system(size: 100))
                        .foregroundColor(.red)
                    
                    Text(soundDetector.lastDetectedSound)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.red)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        // 애니메이션 통합 적용
        .animation(.easeInOut, value: soundDetector.lastDetectedSound)
    }
    
    // Bottom Controls: 모드 전환 버튼
    private var bottomControls: some View {
        VStack(spacing: 15) {
            
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






