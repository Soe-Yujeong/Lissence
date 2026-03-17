//
//  MusicDetailView.swift
//  Lissence
//
//  Created by 서유정 on 3/3/26.
//

import SwiftUI

struct MusicDetailView: View {
    @Binding var currentPath: String

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                //상단 컨트롤 바
                HStack {
                    Button(action: { currentPath = "home" }) {
                        Image(systemName: "house.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                }.padding(.horizontal)
                    .frame(height: 60)
                    
                    .overlay {
                        Text("음악 모드")
                            .font(.system(size: 40, weight: .bold))
                            .offset(y:130)
                    }
                    
                    Spacer()
                
                //중앙 핵심 콘텐츠
                VStack(spacing: 25) {
                    Image(systemName: "music.quarternote.3")
                        .font(.system(size: 90))
                        .foregroundColor(.purple)
                    
                    Text("음악 분석 중..")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Spacer()

                //모드 전환 버튼
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
    }
}
