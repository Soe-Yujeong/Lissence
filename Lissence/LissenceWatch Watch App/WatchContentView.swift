/// 워치의 컨텐츠 뷰(표시)

import SwiftUI

struct WatchContentView: View {
    @StateObject var connectivity = ConnectivityManager.shared
    
    var body: some View {
        NavigationStack {
            List {
                // 감지 모드 섹션
                NavigationLink(destination: WatchDetectionView()) {
                    Label("감지 모드", systemImage: "waveform.and.mic")
                        .foregroundColor(.blue)
                }
                
                // 음악 모드 섹션
                NavigationLink(destination: WatchMusicView()) {
                    Label("음악 모드", systemImage: "music.note.list")
                        .foregroundColor(.purple)
                }
            }
            .navigationTitle("Lissence")
        }
    }
}


