/// 음악모드 

import SwiftUI

struct WatchMusicView: View {
    var body: some View {
        VStack {
            Text("음악 모드")
                .font(.headline)
            Spacer()
            // 추후 여기에 파티클 애니메이션이 들어갑니다.
            Circle()
                .frame(width: 50, height: 50)
                .foregroundColor(.purple)
        }
        //.navigationTitle("음악 모드")
    }
}
