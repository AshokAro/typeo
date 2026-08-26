//
//  GalleryView.swift
//  Typeo
//
//  v2 gallery. Tap a saved composition to reopen it in the editor and keep working.
//

import SwiftUI

struct GalleryView: View {
    let library: CompositionLibrary
    let pins: WidgetPinStore
    /// Called when a composition is chosen, so the editor can take it over.
    let onOpen: (Composition) -> Void

    @State private var pendingDeletion: Composition?

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if library.compositions.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Gallery")
            .background(Color.black)
        }
        .confirmationDialog(
            "Delete this composition?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion {
                    pins.unpin(pendingDeletion.id)   // otherwise the widget keeps a dangling entry
                    library.delete(pendingDeletion)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(library.compositions) { composition in
                    Button {
                        onOpen(composition)
                    } label: {
                        CompositionThumbnail(composition: composition)
                            .overlay(alignment: .topTrailing) {
                                if pins.isPinned(composition.id) {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(5)
                                        .background(.white, in: .circle)
                                        .padding(6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open") { onOpen(composition) }
                        Button("Delete", role: .destructive) { pendingDeletion = composition }
                    }
                }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing saved yet", systemImage: "square.stack")
        } description: {
            Text("Compositions you save from the canvas show up here.")
        }
    }
}

struct CompositionThumbnail: View {
    let composition: Composition

    @State private var image: UIImage?

    var body: some View {
        // Uniform square tiles. Compositions letterbox inside, so a 9:16 next to a
        // 16:9 does not leave ragged holes in the grid.
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 4))
                    .padding(7)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 5) {
                Text(composition.aspectRatio.label)
                if composition.globalShader.kind != .none {
                    Text("· \(composition.globalShader.kind.label)")
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: .rect(cornerRadius: 5))
            .padding(6)
        }
        .task(id: composition) {
            image = CompositionRenderer.render(composition, time: 0, scale: 0.3)
        }
        .accessibilityLabel(composition.text.isEmpty ? "Empty composition" : composition.text)
    }
}
