/// 아이폰과 워치 사이를 연결하는 무전기

import Foundation
import WatchConnectivity
import Combine

// 1. 주고받을 데이터의 '규격' (UIKit의 Model 구조체와 같습니다)
struct MessageData: Codable {
    let title: String      // 알림 메시지 내용
    let iconName: String   // 표시할 아이콘 이름
    let isDanger: Bool     // 위험 여부 (색상 결정용)
}

// 2. 통신 매니저 (UIKit의 ViewModel 또는 Manager 객체 역할)
// ObservableObject: "내 내부 데이터가 바뀌면 화면(View)한테 바로 알려줄게!"라는 뜻입니다.
/// 아이폰과 애플워치 간의 데이터를 송수신하는 통신 매니저
final class ConnectivityManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = ConnectivityManager() // 어디서든 접근 가능한 싱글톤
    
    // @Published: UIKit에서 'didSet { label.text = newValue }' 하던 걸 자동으로 해줍니다.
    // 이 값이 바뀌면 이 변수를 쓰는 모든 SwiftUI 화면이 알아서 새로고침됩니다.
    // MARK: - Published Properties
    /// 워치로부터 전달받은 최신 메시지 (뷰에서 관찰 대상)
    @Published var receivedMessage: MessageData?
    /// 호출 감지 트리거 카운터 (같은 키워드 반복 감지 대응)
    @Published var callingTrigger: Int = 0
    
    // MARK: - Initialization
    override private init() {
        super.init()
        // 세션(무전기 채널)이 지원되는 기기인지 확인하고 활성화합니다.
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // MARK: - Sending Logic
    /// 상대 기기로 MessageData를 전송합니다.
    func send(message: MessageData) {
        guard WCSession.default.isReachable else {
            print("연결 실패")
            return
        }
        if let data = try? JSONEncoder().encode(message),
           let dictionary = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            WCSession.default.sendMessage(dictionary, replyHandler: nil)
        }
    }

    /// 워치 → 아이폰: 오디오 버퍼 Data 전송
    func sendAudioData(_ data: Data) {
        guard WCSession.default.isReachable else {
            print("연결 실패 - 오디오 데이터 전송 불가")
            return
        }
        WCSession.default.sendMessageData(data, replyHandler: nil) { error in
            print("오디오 데이터 전송 실패: \(error)")
        }
    }

    /// 아이폰에서 워치 오디오 수신 시 호출되는 콜백
    var onAudioDataReceived: ((Data) -> Void)?
}

// MARK: - WCSessionDelegate
// 3. 무전기 신호를 수신하는 곳 (Delegate 패턴 - UIKit과 동일합니다)
extension ConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    // ★ MessageData 수신 (기존)
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            if let data = try? JSONSerialization.data(withJSONObject: message, options: []),
               let decoded = try? JSONDecoder().decode(MessageData.self, from: data) {
                self.receivedMessage = decoded
                // 호출 감지 메시지면 카운터 증가 (같은 키워드 반복 감지 대응)
                if !decoded.isDanger {
                    self.callingTrigger += 1
                }
            }
        }
    }

    // ★ 워치에서 보낸 오디오 Data 수신 (신규)
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        DispatchQueue.main.async {
            self.onAudioDataReceived?(messageData)
        }
    }
    
    #if os(iOS) // 아이폰 전용 필수 델리게이트 메서드들
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate() // 세션이 끊기면 다시 살려내기
    }
    #endif
}
