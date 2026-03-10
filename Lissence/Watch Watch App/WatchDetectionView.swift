/// 감지모드

import SwiftUI

struct WatchDetectionView: View {
    @StateObject var connectivity = ConnectivityManager.shared

    var body: some View {
        VStack {
//            Text("감지 모드")
//                .font(.headline)
//            Spacer()
            // 추후 여기에 소리 감지 결과나 텍스트가 표시됩니다.
            // if let 문법을 사용하여 데이터가 있을 때만 아이콘과 글자를 그립니다. (조건부 렌더링)
            if let message = connectivity.receivedMessage {
                Image(systemName: message.iconName) // 아이콘 그리기
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(message.isDanger ? .red : .green) // 위험하면 빨간색
                
                Text(message.title) // 글자 그리기
                    .font(.system(size: 15, weight: .bold))
                    // .onChange: 데이터가 바뀌는 순간을 감지합니다.
                    .onChange(of: connectivity.receivedMessage?.title) {
                        // ★ 여기가 핵심! 데이터 수신 시 워치 손목에 진동을 울립니다.
                        WKInterfaceDevice.current().play(.notification)
                    }
            } else {
                // 데이터가 없을 때 보여줄 기본 화면 (UIKit의 Placeholder 역할)
                ProgressView()
                Text("소리 대기 중...")
                    .font(.footnote)
                    .padding(.top, 5)
            }
        }
        .navigationTitle("감지 모드")
    }
}
