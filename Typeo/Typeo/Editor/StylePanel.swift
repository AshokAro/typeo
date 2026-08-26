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

                Section("Effect") {
                    Picker("Effect", selection: effectKindBinding) {
                        ForEach(ShaderEffect.Kind.allCases) { kind in
                            Text(kind.label).tag(kind)
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
