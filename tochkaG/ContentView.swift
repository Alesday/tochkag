// ContentView.swift
// TochkaG
//
// Главный экран приложения

import SwiftUI

struct ContentView: View {
    @StateObject private var store = ConfigStore()

    var body: some View {
        NavigationView {
            ConfigListView()
                .environmentObject(store)
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }
}
