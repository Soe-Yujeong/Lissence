/// 감지모드

import SwiftUI
import WatchKit

struct WatchDetectionView: View {
    @StateObject var connectivity = ConnectivityManager.shared
    @StateObject var watchSoundDetector = WatchSoundDetector()

    @State private var showCallingAlert = false
    @State private var detectedKeyword = ""

    var body: some View {
        VStack(spacing: 8) {
            // ★ 워치에서 직접 감지된 소리 (워치 → 아이폰으로도 전송됨)
            if !watchSoundDetector.lastDetectedSound.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: getIconForSound(watchSoundDetector.lastDetectedSound))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.red)

                    Text(watchSoundDetector.lastDetectedSound)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            // ★ 아이폰에서 감지되어 워치로 전송된 소리 (위험 감지)
            else if let message = connectivity.receivedMessage, message.isDanger {
                Image(systemName: message.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.red)

                Text(message.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .onChange(of: connectivity.receivedMessage?.title) {
                        WKInterfaceDevice.current().play(.notification)
                    }
            }
            // ★ 감지 대기 중
            else {
                ProgressView()
                Text("소리 대기 중...")
                    .font(.footnote)
                    .padding(.top, 5)
            }
        }
        .navigationTitle("감지 모드")
        .onAppear {
            watchSoundDetector.startDetection()
        }
        .onDisappear {
            watchSoundDetector.stopDetection()
        }
        // 워치에서 소리 감지 시 햅틱 알림
        .onChange(of: watchSoundDetector.lastDetectedSound) {
            if !watchSoundDetector.lastDetectedSound.isEmpty {
                WKInterfaceDevice.current().play(.notification)
            }
        }
        // 호출 감지 시 풀스크린 알림 (카운터 관찰로 같은 키워드 반복도 감지)
        .onChange(of: connectivity.callingTrigger) {
            guard let message = connectivity.receivedMessage else { return }
            // "'저기요' 감지됨" 에서 키워드만 추출
            let title = message.title
            if let start = title.firstIndex(of: "'"),
               let end = title.lastIndex(of: "'"),
               start != end {
                detectedKeyword = String(title[title.index(after: start)..<end])
            } else {
                detectedKeyword = title
            }
            showCallingAlert = true
            WKInterfaceDevice.current().play(.directionUp)
            WKInterfaceDevice.current().play(.directionUp)
        }
        .fullScreenCover(isPresented: $showCallingAlert) {
            CallingAlertView(keyword: detectedKeyword, isPresented: $showCallingAlert)
        }
    }

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

// MARK: - 호출 감지 풀스크린 알림
struct CallingAlertView: View {
    let keyword: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.wave.2.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundColor(.yellow)

            Text("누군가가\n나를 불러요")
                .font(.system(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            Text("'\(keyword)'")
                .font(.system(size: 13))
                .foregroundColor(.yellow)

            Button(action: {
                isPresented = false
            }) {
                Text("확인")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.yellow)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding()
        .onAppear {
            // 5초 후 자동 닫기
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                isPresented = false
            }
        }
    }
}
