//
//  WidgetPickerSheet.swift
//  Typeo
//
//  Choosing what the widget cycles through, from inside the Widget tab. Picking this
//  in the Gallery meant deciding what the widget shows in a screen that says nothing
//  about widgets.
//

import SwiftUI

struct WidgetPickerSheet: View {
    let library: CompositionLibrary
    let pins: WidgetPinStore

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if library.compositions.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing saved yet", systemImage: "square.stack")
                    } description: {
                        Text("Save a composition from the canvas and it will show up here.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(library.compositions) { composition in
                                Button {
                                    if pins.isPinned(composition.id) {
                                        pins.unpin(composition.id)
                                    } else {
                                        pins.pin(composition)
                                    }
                                } label: {
                                    tile(for: composition)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Show in Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func tile(for composition: Composition) -> some View {
        let selected = pins.isPinned(composition.id)
        return ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05))
            CompositionThumbnail(composition: composition)
                .padding(5)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.accentColor : Color.white.opacity(0.12),
                        lineWidth: selected ? 2.5 : 1)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(selected ? Color.accentColor : Color.white.opacity(0.5))
                .padding(7)
        }
        .accessibilityLabel(composition.text.isEmpty ? "Untitled" : composition.text)
        .accessibilityValue(selected ? "In widget" : "Not in widget")
    }
}
