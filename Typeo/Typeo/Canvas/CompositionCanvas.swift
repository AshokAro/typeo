//
//  CompositionCanvas.swift
//  Typeo
//
//  THE EXPORTABLE VIEW. Content only — never chrome, never Liquid Glass.
//  The editor scales this down for display; the exporter renders this exact view
//  at the same logical size. Both paths run the same code, so WYSIWYG is structural.
//

import SwiftUI

struct BackgroundView: View {
    let background: Background

    var body: some View {
        switch background {
        case let .solid(rgba):
            rgba.color
        case let .linearGradient(colors, angleDegrees):
            LinearGradient(
                colors: colors.map(\.color),
                startPoint: UnitPoint(
                    x: 0.5 - 0.5 * cos(angleDegrees * .pi / 180),
                    y: 0.5 - 0.5 * sin(angleDegrees * .pi / 180)
                ),
                endPoint: UnitPoint(
                    x: 0.5 + 0.5 * cos(angleDegrees * .pi / 180),
                    y: 0.5 + 0.5 * sin(angleDegrees * .pi / 180)
                )
            )
        }
    }
}

struct GlyphView: View {
    let glyph: Glyph

    var body: some View {
        Text(verbatim: glyph.character)
            .font(glyph.font.font(size: glyph.size))
            .foregroundStyle(glyph.color.color)
            .fixedSize()
            .rotationEffect(.degrees(glyph.rotation))
            .offset(x: glyph.positionOffset.x, y: glyph.positionOffset.y)
            .layoutValue(key: GlyphRoleKey.self, value: glyph.role)
    }
}

struct CompositionCanvas: View {
    let composition: Composition

    /// Fraction of canvas width the text block may occupy.
    private let textInset: CGFloat = 0.88

    var body: some View {
        let reference = composition.aspectRatio.referenceSize
        let dominant = composition.dominantSize

        ZStack {
            BackgroundView(background: composition.background)

            GlyphFlowLayout(
                lineSpacing: dominant * 0.14,
                fallbackLineHeight: dominant * 0.9
            ) {
                ForEach(composition.glyphs) { glyph in
                    GlyphView(glyph: glyph)
                }
            }
            .frame(maxWidth: reference.width * textInset)
        }
        .frame(width: reference.width, height: reference.height)
        .clipped()
    }
}

#Preview {
    let store = CompositionStore()
    store.setText("Typeo")
    return CompositionCanvas(composition: store.composition)
        .scaleEffect(0.3)
        .frame(width: 324, height: 324)
}
