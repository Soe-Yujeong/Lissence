/// 상황별 진동 제어기

import WatchKit
import Foundation

class HapticController {

    static let shared = HapticController()
    private var lastHapticTime: Date = .distantPast
    private let cooldown: TimeInterval = 1.0 // 생활모드는 1초 쿨다운

    func play(for sound: DangerSound) {
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) > cooldown else { return }
        lastHapticTime = now

        switch sound {
        case .siren:
            // 사이렌 - 강하고 반복적인 진동
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WKInterfaceDevice.current().play(.success)
            }
        case .carHorn:
            // 경적 - 강한 단발 진동
            WKInterfaceDevice.current().play(.notification)
        case .speech:
            // 음성 - 부드러운 진동
            WKInterfaceDevice.current().play(.click)
        case .unknown:
            break
        }
    }
}
