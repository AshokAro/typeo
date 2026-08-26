//
//  FillRail.swift
//  Typeo
//
//  Text and background fills, edited from a rail on the RIGHT EDGE rather than a
//  bottom sheet. The old sheet covered the canvas, so you could not see the colour you
//  were dragging. This panel is narrow and sits beside the canvas instead.
//

import SwiftUI

enum FillTarget: String, Identifiable, CaseIterable {
    case text, background
    var id: String { rawValue }
    var label: String { self == .text ? "Text" : "Background" }
    var systemImage: String { self == .text ? "textformat" : "square.fill" }
}

struct FillRail: View {
    let store: CompositionStore
    @Binding var active: FillTarget?

    var body: some View {
        // No GlassEffectContainer here: it is for morphing between glass shapes, and
        // wrapping a fixed rail in one made the capsule size to the wrong bounds so the
        // chips overflowed it.
        VStack(spacing: 8) {
            ForEach(FillTarget.allCases) { target in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        active = (active == target) ? nil : target
                    }
                } label: {
                    FillChip(paint: paint(for: target), isSelected: active == target)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(target.label) fill")
            }
        }
        .padding(7)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
    }

    private func paint(for target: FillTarget) -> FillPreview {
        switch target {
        case .text:
            if let gradient = store.textGradient { return .gradient(gradient) }
            return .solid(store.style.color)
        case .background:
            if let gradient = store.backgroundGradient { return .gradient(gradient) }
            if case let .solid(rgba) = store.composition.background { return .solid(rgba) }
            return .solid(.black)
        }
    }
}

enum FillPreview {
    case solid(RGBAColor)
    case gradient(GradientPaint)
}

struct FillChip: View {
    let paint: FillPreview
    var isSelected: Bool = false
    /// Text fills carry an A so the two chips are not two identical blobs.
    var glyph: String?

    var body: some View {
        ZStack {
            switch paint {
            case let .solid(rgba):
                Circle().fill(rgba.color)
            case let .gradient(gradient):
                Circle().fill(gradient.linearGradient)
            }

            if let glyph {
                Text(verbatim: glyph)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(contrasting)
            }
        }
        .frame(width: 30, height: 30)
        .overlay(
            Circle().stroke(isSelected ? Color.white : Color.white.opacity(0.35),
                            lineWidth: isSelected ? 2.5 : 1)
        )
    }

    /// Black on light fills, white on dark ones, so the A never disappears.
    private var contrasting: Color {
        let rgba: RGBAColor = switch paint {
        case let .solid(colour): colour
        case let .gradient(gradient): gradient.start
        }
        let luminance = 0.299 * rgba.red + 0.587 * rgba.green + 0.114 * rgba.blue
        return luminance > 0.55 ? .black : .white
    }
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

// MARK: - Editor panel

struct FillEditor: View {
    let store: CompositionStore
    let target: FillTarget

    private let swatches: [RGBAColor] = [
        .white, RGBAColor(red: 0.08, green: 0.09, blue: 0.08),
        RGBAColor(red: 1, green: 0.24, blue: 0.24),
        RGBAColor(red: 1, green: 0.62, blue: 0.15),
        RGBAColor(red: 1, green: 0.9, blue: 0.25),
        RGBAColor(red: 0.35, green: 0.9, blue: 0.45),
        RGBAColor(red: 0.25, green: 0.7, blue: 1),
        RGBAColor(red: 0.62, green: 0.4, blue: 1),
        RGBAColor(red: 1, green: 0.45, blue: 0.8),
    ]

    private var isGradient: Bool {
        target == .text ? store.textGradient != nil : store.backgroundGradient != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(target.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            modeToggle

            if isGradient {
                gradientControls
            } else {
                solidControls
            }
        }
        .padding(12)
        .frame(width: 196)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var modeToggle: some View {
        HStack(spacing: 6) {
            toggleButton("Solid", active: !isGradient) { applySolid() }
            toggleButton("Gradient", active: isGradient) { applyGradient(.sunset) }
        }
    }

    private func toggleButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(active ? Color.accentColor : Color.white.opacity(0.1),
                            in: .rect(cornerRadius: 9))
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var solidControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, rgba in
                    Button { setSolid(rgba) } label: {
                        Circle()
                            .fill(rgba.color)
                            .frame(height: 26)
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            ColorPicker("Custom", selection: colorBinding, supportsOpacity: false)
                .font(.system(size: 12))
        }
    }

    private var gradientControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(GradientPaint.presets.enumerated()), id: \.offset) { _, preset in
                    Button { applyGradient(preset) } label: {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(preset.linearGradient)
                            .frame(height: 30)
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let current = currentGradient {
                ColorPicker("From", selection: stopBinding(index: 0), supportsOpacity: false)
                    .font(.system(size: 12))
                ColorPicker("To", selection: stopBinding(index: 1), supportsOpacity: false)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Angle  \(Int(current.angleDegrees))°")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Slider(value: angleBinding, in: 0...360)
                }
            }
        }
    }

    // MARK: State plumbing

    private var currentGradient: GradientPaint? {
        target == .text ? store.textGradient : store.backgroundGradient
    }

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
