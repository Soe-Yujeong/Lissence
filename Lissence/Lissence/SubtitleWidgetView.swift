/// 감지 모드의 실시간 자막 코드입니다.

import SwiftUI

struct SubtitleWidgetView: View {
    @Binding var isShowing: Bool
    let text: String
    
    @State private var detent: PresentationDetent = .height(350)

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // MARK: - 1. 헤더 (X 버튼)
            HStack {
                Text("실시간 자막")
                    .font(.caption).bold().foregroundColor(.yellow)
                Spacer()
                Button(action: { isShowing = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundColor(.white.opacity(0.6))
                }
            }
            .padding([.top, .horizontal], 20)

            // MARK: - 자막 내용 (위로 올리면 자동으로 전체 화면처럼 보임)
            ScrollView {
                Text(text)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .presentationDetents([.height(350), .large], selection: $detent)
        .presentationDragIndicator(.visible) // 손잡이
    }
}
