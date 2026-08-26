//
//  StylePanel.swift
//  Typeo
//
//  v1: one colour, one size, one effect — every control writes the SAME value to
//  EVERY glyph via CompositionStore. A second effect means you are in v2.
//
//  v6: text and background are separate layers with their own fill AND their own
//  shader, so the tab is the first thing in the sheet and everything below follows it.
//

import SwiftUI

struct StylePanel: View {
    let store: CompositionStore
    @Environment(\.dismiss) private var dismiss
    @State private var target: StyleTarget = .text

    private var activeEffect: ShaderEffect {
        target == .text ? store.composition.globalShader : store.backgroundShader
    }

    private var kindBinding: Binding<ShaderEffect.Kind> {
        Binding(
            get: { activeEffect.kind },
            set: { newValue in
                if target == .text { store.setEffectKind(newValue) }
                else { store.setBackgroundEffectKind(newValue) }
            }
        )
    }

    private func value(for control: EffectControl) -> Double {
        switch control.slot {
        case .intensity: activeEffect.intensity
        case .secondary: activeEffect.resolvedSecondary
        case .tertiary:  activeEffect.resolvedTertiary
        }
    }

    private func binding(for control: EffectControl) -> Binding<Double> {
        Binding(
            get: { value(for: control) },
            set: { newValue in
                store.updateEffect(background: target == .background) { effect in
                    switch control.slot {
                    case .intensity: effect.intensity = newValue
                    case .secondary: effect.secondary = newValue
                    case .tertiary:  effect.tertiary = newValue
                    }
                }
            }
        )
    }

    private var variantBinding: Binding<Int> {
        Binding(
            get: { activeEffect.resolvedVariant },
            set: { newValue in
                store.updateEffect(background: target == .background, coalesceFor: 0) { effect in
                    effect.variant = newValue
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // A preset writes both layers at once, so it sits ABOVE the tab rather
                // than inside one of them.
                presetStrip

                Picker("Applies to", selection: $target) {
                    ForEach(StyleTarget.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Form {
                    Section("Fill") {
                        FillControls(store: store, target: target)
                    }

                    Section("Effect") {
                        Picker("Effect", selection: kindBinding) {
                            ForEach(ShaderEffect.Kind.selectable) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }

                        // Built from the kind's own control list, so an effect that
                        // needs three knobs gets three.
                        ForEach(activeEffect.controls) { control in
                            effectSlider(control)
                        }

                        if let variants = activeEffect.variants {
                            variantRow(variants)
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

    @ViewBuilder
    private func variantRow(_ variants: EffectVariants) -> some View {
        if let names = variants.names {
            Picker(variants.label, selection: variantBinding) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .pickerStyle(.segmented)
        } else {
            HStack {
                Text(variants.label)
                Spacer()
                Text("\(activeEffect.resolvedVariant + 1) / \(variants.count)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    // Roll a DIFFERENT one: rolling the same shape twice reads as a
                    // broken button.
                    var next = activeEffect.resolvedVariant
                    while next == activeEffect.resolvedVariant, variants.count > 1 {
                        next = Int.random(in: 0..<variants.count)
                    }
                    variantBinding.wrappedValue = next
                } label: {
                    Image(systemName: "die.face.5")
                        .font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle \(variants.label)")
            }
        }
    }

    /// Each control carries its own range, so a bipolar one gets the snapping slider
    /// and a signed readout rather than being forced into 0...1.
    private func effectSlider(_ control: EffectControl) -> some View {
        let current = value(for: control)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(control.label)
                Spacer()
                Text(readout(current, bipolar: control.isBipolar))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            SnappingSlider(value: binding(for: control), range: control.range)
                .accessibilityLabel(control.label)
                .accessibilityValue(readout(current, bipolar: control.isBipolar))
        }
    }

    private func readout(_ value: Double, bipolar: Bool) -> String {
        let percent = Int((value * 100).rounded())
        guard bipolar else { return "\(percent)%" }
        if percent > 0 { return "+\(percent)%" }
        if percent < 0 { return "\(percent)%" }
        return "0%"
    }

    private var presetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StylePreset.all) { preset in
                    Button {
                        store.apply(preset)
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(preset.previewBackground)
                                Text(verbatim: "Aa")
                                    .font(preset.font.font(size: 20))
                                    .foregroundStyle(preset.previewGradient)
                            }
                            .frame(width: 54, height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1))

                            Text(preset.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
