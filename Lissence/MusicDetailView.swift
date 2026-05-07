//
//  MusicDetailView.swift
//  Lissence
//
//  Created by 서유정 on 3/3/26.
//
import SwiftUI
import RiveRuntime

struct MusicDetailView: View {
    @Binding var currentPath: String

    @StateObject private var riveModel = RiveViewModel(fileName: "lissence_emotion")
    @StateObject private var engine = MusicAudioEngine()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 상단 컨트롤 바
                HStack {
                    Button(action: { currentPath = "home" }) {
                        Image(systemName: "house.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .frame(height: 60)
                .overlay {
                    Text("음악 모드")
                        .font(.system(size: 40, weight: .bold))
                        .offset(y: 130)
                }

                Spacer()

                VStack(spacing: 36) {
                    riveModel.view()
                        .frame(width: 300, height: 300)

                    Text(engine.isRunning ? moodKorean(engine.mood) : engine.statusText)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut, value: engine.mood)

                    Button(action: toggleEngine) {
                        HStack(spacing: 8) {
                            Image(systemName: engine.isRunning ? "stop.fill" : "play.fill")
                            Text(engine.isRunning ? "분석 중지" : "분석 시작")
                        }
                        .font(.headline)
                        .frame(width: 150, height: 50)
                        .frame(height: 50)
                        .background(engine.isRunning ? Color.red : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                }

                Spacer()

                Button(action: { currentPath = "detection" }) {
                    Label("감지 모드 전환", systemImage: "waveform")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
        // mood 변화 → Rive mood 입력
        .onChange(of: engine.mood) { _, newMood in
            riveModel.setInput("mood", value: newMood.riveValue)
        }
        // intensity 변화 → Rive intensity 입력 (0~1)
        .onChange(of: engine.intensity) { _, newValue in
            riveModel.setInput("intensity", value: Double(newValue))
        }
        // beatPulse 변화 → Rive volume_spike 펄스
        .onChange(of: engine.beatPulse) { _, _ in
            riveModel.setInput("volume_spike", value: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                riveModel.setInput("volume_spike", value: 0.0)
            }
        }
        .onDisappear {
            engine.stop()
        }
    }

    private func toggleEngine() {
        if engine.isRunning {
            engine.stop()
        } else {
            engine.start()
        }
    }

    private func moodKorean(_ m: Mood) -> String {
        switch m {
        case .happy:   return "Happy 🙂"
        case .angry:   return "Angry 😡"
        case .sad:     return "Sad 😢"
        case .relaxed: return "Relaxed 😌"
        }
    }
}
