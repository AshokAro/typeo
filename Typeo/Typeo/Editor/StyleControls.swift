//
//  StyleControls.swift
//  Typeo
//
//  Fill editing used to live in a rail beside the canvas, because a bottom sheet
//  covered the artwork. The sheet now shrinks the canvas to the space above it, so
//  fill and effect sit together in one panel under a single Text / Background tab —
//  one place to change how a layer looks, rather than two.
//

import SwiftUI

/// The layer every control in the style sheet is addressing. Fill and effect both
/// follow it, so the tab is chosen once at the top rather than per section.
enum StyleTarget: String, CaseIterable, Identifiable {
    case text, background

    var id: String { rawValue }
    var label: String { self == .text ? "Text" : "Background" }
}

extension GradientPaint {
    var linearGradient: LinearGradient {
        let radians = angleDegrees * .pi / 180
        return LinearGradient(
            colors: colors.map(\.color),
            startPoint: UnitPoint(x: 0.5 - 0.5 * cos(radians), y: 0.5 - 0.5 * sin(radians)),
            endPoint: UnitPoint(x: 0.5 + 0.5 * cos(radians), y: 0.5 + 0.5 * sin(radians))
        )
    }
}

/// Rows for one Form section. Solid and gradient are the same two cases the model
/// already carries, so this writes straight through to the store.
struct FillControls: View {
    let store: CompositionStore
    let target: StyleTarget

    private let swatches: [RGBAColor] = [
        .white, RGBAColor(red: 0.08, green: 0.09, blue: 0.08),
        RGBAColor(red: 1, green: 0.24, blue: 0.24),
        RGBAColor(red: 1, green: 0.62, blue: 0.15),
        RGBAColor(red: 1, green: 0.9, blue: 0.25),
        RGBAColor(red: 0.35, green: 0.9, blue: 0.45),
        RGBAColor(red: 0.25, green: 0.7, blue: 1),
        RGBAColor(red: 0.62, green: 0.4, blue: 1),
        RGBAColor(red: 1, green: 0.45, blue: 0.8),
        RGBAColor(red: 0.55, green: 0.55, blue: 0.6),
    ]

    private var currentGradient: GradientPaint? {
        target == .text ? store.textGradient : store.backgroundGradient
    }

    private var isGradient: Bool { currentGradient != nil }

    var body: some View {
        Group {
            Picker("Fill", selection: Binding(
                get: { isGradient },
                set: { wantsGradient in
                    if wantsGradient { applyGradient(currentGradient ?? .sunset) }
                    else { applySolid() }
                }
            )) {
                Text("Solid").tag(false)
                Text("Gradient").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isGradient {
                gradientPresets
                ColorPicker("From", selection: stopBinding(index: 0), supportsOpacity: false)
                ColorPicker("To", selection: stopBinding(index: 1), supportsOpacity: false)
                angleRow
            } else {
                swatchGrid
                ColorPicker("Custom", selection: colorBinding, supportsOpacity: false)
            }
        }
    }

    private var swatchGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            ForEach(Array(swatches.enumerated()), id: \.offset) { _, rgba in
                Button { setSolid(rgba) } label: {
                    Circle()
                        .fill(rgba.color)
                        .frame(height: 32)
                        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var gradientPresets: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(Array(GradientPaint.presets.enumerated()), id: \.offset) { _, preset in
                Button { applyGradient(preset) } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(preset.linearGradient)
                        .frame(height: 34)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var angleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Angle")
                Spacer()
                Text("\(Int(currentGradient?.angleDegrees ?? 90))°")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: angleBinding, in: 0...360)
        }
    }

    // MARK: State plumbing

    private func applySolid() {
        switch target {
        case .text:       store.setTextGradient(nil)
        case .background: store.setBackgroundGradient(nil)
        }
    }

    private func applyGradient(_ gradient: GradientPaint) {
        switch target {
        case .text:       store.setTextGradient(gradient)
        case .background: store.setBackgroundGradient(gradient)
        }
    }

    private func setSolid(_ rgba: RGBAColor) {
        switch target {
        case .text:
            store.setTextGradient(nil)
            store.setColor(rgba)
        case .background:
            store.setBackground(.solid(rgba))
        }
    }

    private var colorBinding: Binding<Color> {
        target == .text ? store.colorBinding : store.backgroundColorBinding
    }

    private func stopBinding(index: Int) -> Binding<Color> {
        Binding(
            get: {
                guard let gradient = currentGradient,
                      gradient.colors.indices.contains(index) else { return .white }
                return gradient.colors[index].color
            },
            set: { newValue in
                guard var gradient = currentGradient else { return }
                while gradient.colors.count <= index { gradient.colors.append(.white) }
                gradient.colors[index] = RGBAColor(newValue)
                applyGradient(gradient)
            }
        )
    }

    private var angleBinding: Binding<Double> {
        Binding(
            get: { currentGradient?.angleDegrees ?? 90 },
            set: { newValue in
                guard var gradient = currentGradient else { return }
                gradient.angleDegrees = newValue
                applyGradient(gradient)
            }
        )
    }
}
