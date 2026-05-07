//
//  LissenceApp.swift
//  Lissence
//
//  Created by 서유정 on 2/17/26.
//

import SwiftUI

@main
struct LissenceApp: App {
    @State private var currentPath: String = "home"

    var body: some Scene {
        WindowGroup {
            Group {
                if currentPath == "home" {
                    MainHomeView(currentPath: $currentPath)
                } else if currentPath == "detection" {
                    DetectionDetailView(currentPath: $currentPath)
                } else if currentPath == "music" {
                    MusicDetailView(currentPath: $currentPath)
                }
            }
            .animation(.easeInOut, value: currentPath) // 화면 전환
        }
    }
}
