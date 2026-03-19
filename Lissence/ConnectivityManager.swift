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
    
    /// 위험 감지상태의 자동 초기화를 위한 타이머 변수 추가
    private var resetTimer: Timer?
    
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
    /// 상대 기기로 데이터를 전송합니다.
    func send(message: MessageData) {
        // 상대방 기기(워치)가 연결되어 있는지 먼저 확인
        guard WCSession.default.isReachable else {
            print("연결 실패")
            return
        }
        
        // 구조체 데이터를 딕셔너리[String: Any] 형태로 변환해서 보냅니다. (전송 규격)
        if let data = try? JSONEncoder().encode(message),
           let dictionary = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            WCSession.default.sendMessage(dictionary, replyHandler: nil)
        }
    }
}

// MARK: - WCSessionDelegate
// 3. 무전기 신호를 수신하는 곳 (Delegate 패턴 - UIKit과 동일합니다)
extension ConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    // ★ 실제로 상대방이 sendMessage를 했을 때 실행되는 콜백 함수
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // UI 업데이트는 반드시 메인 스레드에서! (UIKit의 DispatchQueue.main.async와 동일)
        DispatchQueue.main.async {
            // 수신 데이터 디코딩 및 UI 업데이트
            if let data = try? JSONSerialization.data(withJSONObject: message, options: []),
               let decoded = try? JSONDecoder().decode(MessageData.self, from: data) {
                
                // 1. 기존 타이머가 있다면 취소 (새로운 메시지가 오면 제한시간 리셋)
                self.resetTimer?.invalidate()
                
                // 2. 메시지 수신 및 UI 업데이트
                self.receivedMessage = decoded // 화면이 바뀝니다.
                print("📩 아이폰으로부터 메시지 수신: \(decoded.title)") // 디버깅용
                
                // 3. 5초 후에 receivedMessage를 nil로 만들어 화면을 대기 상태로 되돌림
                self.resetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.receivedMessage = nil
                        print("♻️ 아이폰 메시지 표시 기한 만료 - 대기 상태 전환")
                    }
                }
            }
        }
    }
    
    #if os(iOS) // 아이폰 전용 필수 델리게이트 메서드들
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate() // 세션이 끊기면 다시 살려내기
    }
    #endif
}
