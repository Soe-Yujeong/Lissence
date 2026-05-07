//
//  RiveView.swift
//  Lissence
//
//  Created by 2248-01 on 4/27/26.
//
import SwiftUI
import RiveRuntime

struct RiveView: View {
    @StateObject private var riveModel = RiveViewModel(fileName: "lissence_2-2", stateMachineName: "State Machine 1")
    
    // intensity 조절을 위한 상태 변수 (0부터 10까지)
    @State private var intensity: Double = 5.0
    
    var body: some View {
        VStack(spacing: 25) {
            
            // 이모지 화면
            riveModel.view()
                .frame(width: 300, height: 300)
            
            // 1. 비트 펀치 테스트 버튼
            HStack(spacing: 15) {
                Button("🎵 얼굴 커지기 (1)") {
                    riveModel.setInput("volume_spike", value: 1.0)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("원래대로 (0)") {
                    riveModel.setInput("volume_spike", value: 0.0)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            
            // 2. 감정 강도 (Intensity) 조절 슬라이더
            VStack(alignment: .leading, spacing: 10) {
                Text("감정 강도 (Intensity): \(String(format: "%.1f", intensity))")
                    .font(.headline)
                
                // 손가락으로 밀 때마다 실시간으로 부드럽게 넘어가도록 적용
                Slider(value: $intensity, in: 0...10)
                    .onChange(of: intensity) { newValue in
                        // 🔥 iOS 런타임 버그 회피: 앱에서는 0~10으로 보여주고, Rive 엔진에는 0.0~1.0으로 쪼개서 전달!
                        riveModel.setInput("intensity", value: newValue / 10.0)
                    }
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
            
            // 3. 4Q 감정 모드 변경 버튼
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    Button("😊 Happy (0)") {
                        riveModel.setInput("mood", value: 0.0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Button("😡 Angry (1)") {
                        riveModel.setInput("mood", value: 1.0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                HStack(spacing: 15) {
                    Button("😢 Sad (2)") {
                        riveModel.setInput("mood", value: 2.0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Button("😌 Relaxed (3)") {
                        riveModel.setInput("mood", value: 3.0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.mint)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    RiveView()
}
