//
//  tochkaGApp.swift
//  tochkaG
//
//  Created by Sasha DAYLI on 08.04.2026.
//

import SwiftUI

@main
struct tochkaGApp: App {
    @StateObject private var store = ConfigStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    // Авто-обновление подписки при каждом запуске приложения
                    store.refreshSubscription()
                }
                .onChange(of: scenePhase) { phase in
                    // При возврате из фона сверяем тумблеры с реальным состоянием
                    // туннеля: он мог остаться поднятым или быть выключен из Настроек.
                    if phase == .active {
                        store.syncActiveStateWithSystem()
                    }
                }
        }
    }
}
