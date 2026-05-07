import SwiftUI

struct ContentView: View {

    @StateObject private var classifier = SoundClassifier()

    var body: some View {
        NavigationStack {
        VStack(spacing: 8) {

            // 감지 상태 아이콘
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 60, height: 60)

                Text(statusEmoji)
                    .font(.system(size: 26))
            }
            .animation(.easeInOut(duration: 0.3), value: classifier.detectedSound)

            // 감지된 소리 텍스트
            Text(statusLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(statusColor)

            // 신뢰도
            if classifier.detectedSound != .unknown {
                Text(String(format: "신뢰도 %.0f%%", classifier.confidence * 100))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            // 시작/정지 버튼
            Button(action: toggle) {
                Text(classifier.isRunning ? "정지" : "시작")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(classifier.isRunning ? Color.red : Color.blue)
        }
        .padding()
        .contentShape(Rectangle())
        .onAppear(perform: setupCallback)
        } // NavigationStack
    }

    private func toggle() {
        classifier.isRunning ? classifier.stop() : classifier.start()
    }

    private func setupCallback() {
        classifier.onDangerDetected = { sound, _ in
            HapticController.shared.play(for: sound)
        }
    }

    // MARK: - 상태별 UI
    private var statusEmoji: String {
        switch classifier.detectedSound {
        case .siren:   return "🚨"
        case .carHorn: return "🚗"
        case .speech:  return "🗣️"
        case .unknown: return classifier.isRunning ? "👂" : "💤"
        }
    }

    private var statusLabel: String {
        switch classifier.detectedSound {
        case .siren:   return "사이렌 감지!"
        case .carHorn: return "경적 감지!"
        case .speech:  return "음성 감지"
        case .unknown: return classifier.isRunning ? "감지 중..." : "대기 중"
        }
    }

    private var statusColor: Color {
        switch classifier.detectedSound {
        case .siren:   return .red
        case .carHorn: return .orange
        case .speech:  return .yellow
        case .unknown: return .gray
        }
    }
}
