//
//  StylePanel.swift
//  Typeo
//
//  v1: one colour, one size, one effect — every control writes the SAME value to
//  EVERY glyph via CompositionStore. A second effect means you are in v2.
//

import SwiftUI

struct StylePanel: View {
    let store: CompositionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Presets") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(StylePreset.all) { preset in
                                Button {
                                    store.apply(preset)
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 9)
                                                .fill(preset.previewBackground)
                                            Text(verbatim: "Aa")
                                                .font(preset.font.font(size: 20))
                                                .foregroundStyle(preset.previewGradient)
                                        }
                                        .frame(width: 56, height: 44)
                                        .overlay(RoundedRectangle(cornerRadius: 9)
                                            .stroke(Color.primary.opacity(0.15), lineWidth: 1))

                                        Text(preset.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 0))
                }

                Section("Text") {
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
                }

                Section("Layout") {
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

                Section("Effect") {
                    Picker("Effect", selection: effectKindBinding) {
                        ForEach(ShaderEffect.Kind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }

                    if store.composition.globalShader.usesSecondary {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(store.composition.globalShader.secondaryLabel)
                                Spacer()
                                Text(store.composition.globalShader.resolvedSecondary,
                                     format: .percent.precision(.fractionLength(0)))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { store.composition.globalShader.resolvedSecondary },
                                set: { store.setEffectSecondary($0) }
                            ), in: 0...1)
                        }
                    }

                    if store.composition.globalShader.kind != .none {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Intensity")
                                Spacer()
                                Text(store.composition.globalShader.intensity, format: .percent.precision(.fractionLength(0)))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: store.intensityBinding, in: 0...1)
                        }
                    }
                }
            }
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var effectKindBinding: Binding<ShaderEffect.Kind> {
        Binding(
            get: { store.composition.globalShader.kind },
            set: { store.setEffectKind($0) }
        )
    }
}
