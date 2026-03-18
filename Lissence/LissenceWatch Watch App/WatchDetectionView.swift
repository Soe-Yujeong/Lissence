/// 감지모드

import SwiftUI

struct WatchDetectionView: View {
    
    /// 기존 : 아이폰 연동 매니저
    @StateObject var connectivity = ConnectivityManager.shared
    /// 추가 : 워치 단독 감지 엔진
    @StateObject private var classifier = SoundClassifier()

    var body: some View {
        VStack {
            // 상황 판별 (아이폰 감지 내용 우선 표시 / 없으면 워치 자체 감지 결과 표시)
            if let message = connectivity.receivedMessage {
                displayInfo(title: message.title, icon: message.iconName, isDanger: message.isDanger, source: "iPhone")
            }
            else if classifier.detectedSound != .unknown {
                // 워치 자체 감지 결과 표시
                displayInfo(title: classifier.detectedSound.label, icon: classifier.detectedSound.icon, isDanger: true, source: "Watch")
           } else {
               // 데이터가 없을 때 보여줄 기본 화면
               ProgressView()
               Text("소리 대기 중...")
                   .font(.footnote)
                   .padding(.top, 5)
           }
        }
        .navigationTitle("감지 모드")
            .onAppear() {
                classifier.start() // 화면 진입 시 워치 마이크 감지 시작
                setupHapticCallBack()
        }
            .onDisappear {
                classifier.stop() // 화면 나가면 중지
            }
        }
    
    // 공통 UI 컴포넌트
    @ViewBuilder
    /// 아이폰에서 수신된 데이터 표시 (자막이나 상세 정보)
    /// - Parameters:
    ///   - title: 위험이름
    ///   - icon: 위험 종류별 아이콘
    ///   - isDanger: 위험한지 여부
    ///   - source: 아이폰 또는 워치
    /// - Returns: 뷰로 반환
    func displayInfo(title: String, icon: String, isDanger: Bool, source: String) -> some View {
        Image(systemName: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)
            .foregroundColor(isDanger ? .red : .green)
        
        Text(title)
            .font(.headline)
        
        Text("\(source)에서 감지됨!")
            .font(.caption2)
            .foregroundColor(.gray)
    }

    /// 워치 자체 감지시 진동 실행
    private func setupHapticCallBack() {
        classifier.onDangerDetected = { sound, confidence in
            HapticController.shared.play(for: sound)
        }
    }
}


