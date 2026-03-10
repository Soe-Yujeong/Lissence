/// 감지모드

import SwiftUI
import WatchKit

struct WatchDetectionView: View {
    @StateObject var connectivity = ConnectivityManager.shared
    @StateObject var watchSoundDetector = WatchSoundDetector()

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
            // ★ 아이폰에서 감지되어 워치로 전송된 소리
            else if let message = connectivity.receivedMessage {
                Image(systemName: message.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(message.isDanger ? .red : .green)

                Text(message.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(message.isDanger ? .red : .green)
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
