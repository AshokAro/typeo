//
//  FontPickerSheet.swift
//  Typeo
//
//  Every row previews the user's ACTUAL typed text, not sample text (CLAUDE.md).
//
//  v6: size and block layout live here too. They are all "how the type is set"
//  decisions, and keeping them beside the typeface leaves the style sheet to fill
//  and effect alone.
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
            Form {
                Section("Size & layout") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Size")
                            Spacer()
                            Text("\(Int(store.style.size))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: store.sizeBinding, in: 40...420, step: 2)
                    }


                    Picker("Alignment", selection: Binding(
                        get: { store.composition.resolvedAlignment },
                        set: { store.setAlignment($0) }
                    )) {
                        ForEach(TextBlockAlignment.allCases) { alignment in
                            Image(systemName: alignment.systemImage).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Letter spacing")
                            Spacer()
                            Text("\(Int(store.composition.resolvedLetterSpacing))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: store.letterSpacingBinding, in: -30...120, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Line height")
                            Spacer()
                            Text(store.composition.resolvedLineHeight, format: .number.precision(.fractionLength(2)))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: store.lineHeightBinding, in: 0.6...2.2)
                    }
                }

                Section("Typeface") {
                    ForEach(FontCatalog.all) { option in
                        Button {
                            store.setFont(option.glyphFont)
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
                }
            }
            .navigationTitle("Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
