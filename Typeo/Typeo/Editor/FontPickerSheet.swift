//
//  FontPickerSheet.swift
//  Typeo
//
//  Every row previews the user's ACTUAL typed text, not sample text (CLAUDE.md).
//

import SwiftUI

struct FontPickerSheet: View {
    let store: CompositionStore
    @Environment(\.dismiss) private var dismiss

    private var previewText: String {
        let typed = store.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? "Typeo" : typed
    }

    var body: some View {
        NavigationStack {
            List(FontCatalog.all) { option in
                Button {
                    store.setFont(option.glyphFont)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: previewText)
                                .font(option.glyphFont.font(size: 28))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .foregroundStyle(.primary)
                            Text(option.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if store.style.font == option.glyphFont {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Font")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
