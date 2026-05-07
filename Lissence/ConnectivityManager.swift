//
//  ConnectivityManager.swift
//  Lissence
//
//  Created by 2248-01 on 3/18/26.
//
import Foundation
import Combine
import WatchConnectivity

struct MessageData: Codable, Equatable {
    var title: String
    var iconName: String
    var isDanger: Bool
}

final class ConnectivityManager: NSObject, ObservableObject {
    
    static let shared = ConnectivityManager()
    
    @Published var receivedMessage: MessageData?
    
    override private init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func send(message: MessageData) {
        guard WCSession.default.isReachable else { return }
        if let encoded = try? JSONEncoder().encode(message) {
            let dict = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] ?? [:]
            WCSession.default.sendMessage(dict, replyHandler: nil, errorHandler: nil)
        }
    }
}

extension ConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            if let data = try? JSONSerialization.data(withJSONObject: message),
               let decoded = try? JSONDecoder().decode(MessageData.self, from: data) {
                self.receivedMessage = decoded
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
