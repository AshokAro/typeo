//
//  StylePanel.swift
//  Typeo
//
//  v1: one colour, one size, one effect — every control writes the SAME value to
//  EVERY glyph via CompositionStore. A second effect means you are in v2.
//

import SwiftUI

enum EffectTarget: String, Hashable {
    case text, background
}

struct StylePanel: View {
    let store: CompositionStore
    @Environment(\.dismiss) private var dismiss
    @State private var effectTarget: EffectTarget = .text

    private var activeEffect: ShaderEffect {
        effectTarget == .text ? store.composition.globalShader : store.backgroundShader
    }

    private var kindBinding: Binding<ShaderEffect.Kind> {
        Binding(
            get: { activeEffect.kind },
            set: { newValue in
                if effectTarget == .text { store.setEffectKind(newValue) }
                else { store.setBackgroundEffectKind(newValue) }
            }
        )
    }

    private var intensityBinding: Binding<Double> {
        Binding(
            get: { activeEffect.intensity },
            set: { newValue in
                if effectTarget == .text { store.setEffectIntensity(newValue) }
                else { store.setBackgroundEffectIntensity(newValue) }
            }
        )
    }

    private var secondaryBinding: Binding<Double> {
        Binding(
            get: { activeEffect.resolvedSecondary },
            set: { newValue in
                if effectTarget == .text { store.setEffectSecondary(newValue) }
                else { store.setBackgroundEffectSecondary(newValue) }
            }
        )
    }

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
                    // Text and background carry separate shaders, so the sheet needs a
                    // target before anything else on this row makes sense.
                    Picker("Applies to", selection: $effectTarget) {
                        Text("Text").tag(EffectTarget.text)
                        Text("Background").tag(EffectTarget.background)
                    }
                    .pickerStyle(.segmented)

                    Picker("Effect", selection: kindBinding) {
                        ForEach(ShaderEffect.Kind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }

                    if activeEffect.kind != .none {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Intensity")
                                Spacer()
                                Text(activeEffect.intensity, format: .percent.precision(.fractionLength(0)))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: intensityBinding, in: 0...1)
                        }

                        if activeEffect.usesSecondary {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(activeEffect.secondaryLabel)
                                    Spacer()
                                    Text(activeEffect.resolvedSecondary, format: .percent.precision(.fractionLength(0)))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: secondaryBinding, in: 0...1)
                            }
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
}
