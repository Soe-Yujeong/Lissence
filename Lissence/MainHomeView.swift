import SwiftUI

struct MainHomeView: View {
    @Binding var currentPath: String // AppMain에서 관리하는 상태를 받아옴

    var body: some View {
        VStack {
            
            VStack {
                VStack(spacing: 10) {
                    Text("LISSENCE")
                        .font(.system(size: 45, weight: .black))
                    
                    Text("원하시는 모드를 선택해주세요")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 60)
            
            Spacer()
                
            // 중앙 버튼
            VStack(spacing: 25) {
                Button(action: { currentPath = "detection" }) {
                    ModeSelectionCard(title: "감지 모드", icon: "waveform.and.mic", color: .blue, description: "주변 소리 및 음성 인식")
                }

                Button(action: { currentPath = "music" }) {
                    ModeSelectionCard(title: "음악 모드", icon: "music.note.list", color: .purple, description: "음악 시각화 및 햅틱 변환")
                }
            }
            .padding(.horizontal, 30)

            Spacer()
        }
    }
}

// 버튼 디자인
struct ModeSelectionCard: View {
    let title: String
    let icon: String
    let color: Color
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.title2).bold()
                Text(description).font(.caption)
            }
            Spacer()
            Image(systemName: icon).font(.largeTitle)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(color)
        .foregroundColor(.white)
        .cornerRadius(25)
        
    }
}
