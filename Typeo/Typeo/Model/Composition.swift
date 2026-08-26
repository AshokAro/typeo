//
//  Composition.swift
//  Typeo
//
//  THE ONE ARCHITECTURAL RULE (see CLAUDE.md):
//  Every character is its own object from v1, even though v1's UI does not expose
//  per-character controls. v1 writes the SAME value to every glyph at once.
//  v3 starts writing DIFFERENT values to individual glyphs. This model does not move.
//

import SwiftUI

// MARK: - Aspect ratio

enum AspectRatio: String, Codable, CaseIterable, Identifiable, Hashable {
    case square    = "1:1"
    case portrait  = "9:16"
    case landscape = "16:9"

    var id: String { rawValue }
    var label: String { rawValue }

    /// The canvas ALWAYS lays out at this fixed logical size, on screen and at export.
    /// On screen it is scaled down; at export it is rendered at `scale`x.
    /// That is what makes WYSIWYG structural rather than hand-maintained.
    var referenceSize: CGSize {
        switch self {
        case .square:    CGSize(width: 1080, height: 1080)
        case .portrait:  CGSize(width: 1080, height: 1920)
        case .landscape: CGSize(width: 1920, height: 1080)
        }
    }

    var ratio: CGFloat { referenceSize.width / referenceSize.height }

    var systemImage: String {
        switch self {
        case .square:    "square"
        case .portrait:  "rectangle.portrait"
        case .landscape: "rectangle"
        }
    }
}

// MARK: - Codable colour

/// `Color` is not `Codable`; v2 persists compositions, so colour is stored as components.
struct RGBAColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let ink   = RGBAColor(red: 0.09, green: 0.10, blue: 0.09)
}

// MARK: - Background

enum Background: Codable, Hashable {
    case solid(RGBAColor)
    case linearGradient(colors: [RGBAColor], angleDegrees: Double)

    static let defaultBackground = Background.solid(.ink)
}

// MARK: - Font

struct GlyphFont: Codable, Hashable {
    /// PostScript name of a bundled/system face. `nil` means the SF system font.
    var fontName: String?
    /// Only meaningful when `fontName == nil`.
    var design: SystemDesign

    enum SystemDesign: String, Codable, Hashable, CaseIterable {
        case standard, rounded, serif, monospaced

        var fontDesign: Font.Design {
            switch self {
            case .standard:   .default
            case .rounded:    .rounded
            case .serif:      .serif
            case .monospaced: .monospaced
            }
        }
    }

    static let system = GlyphFont(fontName: nil, design: .standard)

    /// `fixedSize` deliberately opts out of Dynamic Type — the canvas must render
    /// identically regardless of the reader's text-size setting, or export breaks.
    func font(size: CGFloat) -> Font {
        if let fontName {
            Font.custom(fontName, fixedSize: size)
        } else {
            Font.system(size: size, weight: .semibold, design: design.fontDesign)
        }
    }
}

// MARK: - Effect

/// v1 shipped `bloom` alone. v2 adds heat / noise / glitch — purely additive cases,
/// no reshaping of the model.
struct ShaderEffect: Codable, Hashable {
    var kind: Kind
    var intensity: Double

    enum Kind: String, Codable, CaseIterable, Identifiable, Hashable {
        case none, bloom, heat, noise, glitch

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none:   "None"
            case .bloom:  "Bloom"
            case .heat:   "Heat"
            case .noise:  "Noise"
            case .glitch: "Glitch"
            }
        }

        /// Whether the shader reads `time` and therefore needs a running clock.
        var isAnimated: Bool {
            switch self {
            case .none, .bloom:        false
            case .heat, .noise, .glitch: true
            }
        }

        /// How far the shader may sample outside a pixel. Also sets how much bleed
        /// room the text block is padded with, so the effect is not clipped.
        var sampleOffset: CGFloat {
            switch self {
            case .none:   0
            case .bloom:  60
            case .heat:   60
            case .noise:  0
            case .glitch: 130
            }
        }
    }

    static let none = ShaderEffect(kind: .none, intensity: 0)
}

// MARK: - Glyph

struct Glyph: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Exactly one character. Stored as `String` because `Character` is not `Codable`.
    var character: String
    var font: GlyphFont
    var size: CGFloat
    var color: RGBAColor
    var positionOffset: CGPoint      // default .zero in v1
    var rotation: Double             // degrees, default 0 in v1
    var shaderOverride: ShaderEffect? // nil in v1

    init(
        id: UUID = UUID(),
        character: String,
        font: GlyphFont,
        size: CGFloat,
        color: RGBAColor,
        positionOffset: CGPoint = .zero,
        rotation: Double = 0,
        shaderOverride: ShaderEffect? = nil
    ) {
        self.id = id
        self.character = character
        self.font = font
        self.size = size
        self.color = color
        self.positionOffset = positionOffset
        self.rotation = rotation
        self.shaderOverride = shaderOverride
    }

    var role: GlyphRole {
        if character == "\n" { .lineBreak }
        else if character == " " { .space }
        else { .glyph }
    }
}

nonisolated enum GlyphRole: Hashable {
    case glyph, space, lineBreak
}

// MARK: - Composition

struct Composition: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var aspectRatio: AspectRatio = .square
    var background: Background = .defaultBackground
    var globalShader: ShaderEffect = .none
    var glyphs: [Glyph] = []

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        aspectRatio: AspectRatio = .square,
        background: Background = .defaultBackground,
        globalShader: ShaderEffect = .none,
        glyphs: [Glyph] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.aspectRatio = aspectRatio
        self.background = background
        self.globalShader = globalShader
        self.glyphs = glyphs
    }

    var text: String { glyphs.map(\.character).joined() }
    var isEmpty: Bool { glyphs.isEmpty }

    /// Largest glyph on the canvas — drives line spacing and empty-line height.
    var dominantSize: CGFloat { glyphs.map(\.size).max() ?? 140 }
}
