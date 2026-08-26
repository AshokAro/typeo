//
//  ContentView.swift
//  Typeo
//
//  Screen flow: splash (~1s) -> editor. No onboarding, no login (CLAUDE.md).
//  v2 adds the gallery tab alongside the canvas.
//

import SwiftUI

struct ContentView: View {
    @State private var store = CompositionStore()
    @State private var library = CompositionLibrary()
    @State private var pins = WidgetPinStore()
    @State private var showSplash = true
    @State private var selectedTab = Tabs.canvas

    private enum Tabs { case canvas, gallery, widget }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Canvas", systemImage: "textformat", value: Tabs.canvas) {
                    EditorView(store: store, library: library)
                }
                Tab("Gallery", systemImage: "square.stack", value: Tabs.gallery) {
                    GalleryView(library: library, pins: pins) { composition in
                        store.load(composition)
                        selectedTab = .canvas
                    }
                }
                Tab("Widget", systemImage: "rectangle.grid.2x2", value: Tabs.widget) {
                    WidgetScreen(library: library, pins: pins)
                }
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            #if DEBUG
            if SelfCheck.isRequested { SelfCheck.run() }
            #endif
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
