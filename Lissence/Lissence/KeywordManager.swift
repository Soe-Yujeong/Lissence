/// 호출 키워드 관리
/// - 사용자가 설정에서 키워드를 추가/삭제할 수 있습니다.
/// - UserDefaults에 저장되어 앱 재시작 후에도 유지됩니다.

import Foundation
import SwiftUI
import Combine

class KeywordManager: ObservableObject {

    private let storageKey = "detectionKeywords"

    @Published var keywords: [String] {
        didSet {
            UserDefaults.standard.set(keywords, forKey: storageKey)
        }
    }

    init() {
        self.keywords = UserDefaults.standard.stringArray(forKey: "detectionKeywords")
            ?? ["여기요", "저기요", "이봐요", "잠깐만요", "엄마", "아빠"]
    }

    func add(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !keywords.contains(trimmed) else { return }
        keywords.append(trimmed)
    }

    func remove(at offsets: IndexSet) {
        keywords.remove(atOffsets: offsets)
    }
}
