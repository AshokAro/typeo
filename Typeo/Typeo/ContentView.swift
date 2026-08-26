//
//  ContentView.swift
//  Typeo
//
//  Screen flow: splash (~1s) -> editor. No onboarding, no login (CLAUDE.md).
//

import SwiftUI

struct ContentView: View {
    @State private var store = CompositionStore()
    @State private var showSplash = true

    var body: some View {
        ZStack {
            EditorView(store: store)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeOut(duration: 0.35)) {
                showSplash = false
            }
        }
    }
}

#Preview {
    ContentView()
}
