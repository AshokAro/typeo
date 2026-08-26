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

// MARK: - Text block layout

enum TextBlockAlignment: String, Codable, CaseIterable, Identifiable, Hashable {
    case leading, center, trailing

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .leading:  "text.alignleft"
        case .center:   "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}

// MARK: - Gradient

/// A linear gradient. Used for the text fill; `Background` carries its own case.
struct GradientPaint: Codable, Hashable {
    var colors: [RGBAColor]
    var angleDegrees: Double

    init(colors: [RGBAColor], angleDegrees: Double = 90) {
        self.colors = colors
        self.angleDegrees = angleDegrees
    }

    var start: RGBAColor { colors.first ?? .white }
    var end: RGBAColor { colors.last ?? .white }

    static let sunset = GradientPaint(
        colors: [RGBAColor(red: 1, green: 0.35, blue: 0.25), RGBAColor(red: 0.55, green: 0.15, blue: 0.75)]
    )
    static let ice = GradientPaint(
        colors: [RGBAColor(red: 0.55, green: 0.95, blue: 1), RGBAColor(red: 0.25, green: 0.35, blue: 0.95)]
    )
    static let lime = GradientPaint(
        colors: [RGBAColor(red: 0.85, green: 1, blue: 0.3), RGBAColor(red: 0.1, green: 0.75, blue: 0.45)]
    )
    static let ember = GradientPaint(
        colors: [RGBAColor(red: 1, green: 0.85, blue: 0.3), RGBAColor(red: 0.9, green: 0.15, blue: 0.1)]
    )
    static let presets: [GradientPaint] = [.sunset, .ice, .lime, .ember]
}

// MARK: - Background

enum Background: Codable, Hashable {
    case solid(RGBAColor)
    case linearGradient(colors: [RGBAColor], angleDegrees: Double)
    /// A photo, referenced by id — the pixels live in BackgroundImageStore, never in
    /// the JSON. Adding a case is additive: files written before it still decode,
    /// because Codable keys an enum on the case name.
    case image(id: String)

    static let defaultBackground = Background.solid(.ink)

    var imageID: String? {
        if case let .image(id) = self { return id }
        return nil
    }
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
    /// Second parameter for shaders that need one (motion-blur angle, matrix speed).
    /// Optional for the same decode reason as every other v6 field.
    var secondary: Double?
    /// Third continuous parameter. Optional, so files written before it decode.
    var tertiary: Double?
    /// A DISCRETE choice — noise type, mesh shape. Optional for the same reason.
    var variant: Int?

    enum Kind: String, Codable, CaseIterable, Identifiable, Hashable {
        case none, bloom, heat, noise, glitch
        // v6
        case chrome, glass, matrix, liquify, halftone, motionBlur, thermal
        case neon, gemSmoke, meshGradient, grainGradient, dithering
        case flutedGlass, lensDistort

        var id: String { rawValue }

        /// What the picker offers. Raw values are NEVER removed — Kind is a
        /// non-optional String enum, so deleting a case fails to decode every saved
        /// composition that used it — so a retired effect is hidden here and keeps
        /// rendering for anything already saved.
        static let selectable: [Kind] = allCases.filter { $0 != .gemSmoke }

        var label: String {
            switch self {
            case .none:       "None"
            case .bloom:      "Bloom"
            case .heat:       "Heat"
            case .noise:      "Noise"
            case .glitch:     "Glitch"
            case .chrome:     "Liquid Metal"
            case .glass:      "Glass"
            case .matrix:     "Matrix"
            case .liquify:    "Liquify"
            case .halftone:   "Halftone"
            case .motionBlur: "Motion"
            case .thermal:    "Heatmap"
            case .neon:          "Neon"
            case .gemSmoke:      "Gem Smoke"
            case .meshGradient:  "Mesh"
            case .grainGradient: "Grain"
            case .dithering:     "Dither"
            case .flutedGlass:   "Fluted Glass"
            case .lensDistort:   "Lens"
            }
        }

        /// Whether the shader reads `time` and therefore needs a running clock.
        var isAnimated: Bool {
            switch self {
            case .none, .bloom, .glass, .halftone, .motionBlur, .thermal, .neon, .dithering:
                false
            case .heat, .noise, .glitch, .chrome, .matrix, .liquify,
                 .gemSmoke, .meshGradient, .grainGradient:
                true
            case .flutedGlass, .lensDistort:
                false
            }
        }

        /// How far the shader may sample outside a pixel. Also sets how much bleed
        /// room the text block is padded with, so the effect is not clipped.
        var sampleOffset: CGFloat {
            switch self {
            case .none:       0
            case .bloom:      60
            case .heat:       60
            case .noise:      0
            case .glitch:     130
            case .chrome:     0
            case .glass:      70
            case .matrix:     0
            case .liquify:    90
            case .halftone:   0
            case .motionBlur: 130
            case .thermal:       70
            case .neon:          90
            case .gemSmoke:      0
            case .meshGradient:  0
            case .grainGradient: 0
            case .dithering:     0
            case .flutedGlass:   90
            case .lensDistort:   120
            }
        }
    }

    static let none = ShaderEffect(kind: .none, intensity: 0)

    var resolvedSecondary: Double { secondary ?? 0.5 }
    var resolvedTertiary: Double { tertiary ?? 0.5 }
    var resolvedVariant: Int { variant ?? 0 }

    /// The sliders this effect actually offers. Every effect has an intensity; the
    /// rest are per-effect, which is why the panel builds itself from this rather than
    /// hardcoding one "secondary" row.
    var controls: [EffectControl] {
        switch kind {
        case .none:       []
        case .bloom:      [.init(.intensity, "Glow"), .init(.secondary, "Spread")]
        case .heat:       [.init(.intensity, "Distortion"), .init(.secondary, "Temperature"),
                           .init(.tertiary, "Speed")]
        case .noise:      [.init(.intensity, "Amount"), .init(.secondary, "Size")]
        case .glitch:     [.init(.intensity, "Amount"), .init(.secondary, "Slice")]
        case .chrome:     [.init(.intensity, "Amount"), .init(.secondary, "Flow"),
                           .init(.tertiary, "Contrast")]
        case .glass:      [.init(.intensity, "Refraction"), .init(.secondary, "Frost")]
        case .matrix:     [.init(.intensity, "Amount"), .init(.secondary, "Speed"),
                           .init(.tertiary, "Density")]
        case .liquify:    [.init(.intensity, "Amount"), .init(.secondary, "Scale"),
                           .init(.tertiary, "Speed")]
        case .halftone:   [.init(.intensity, "Amount"), .init(.secondary, "Dot size"),
                           .init(.tertiary, "Gooey")]
        case .motionBlur: [.init(.intensity, "Length"), .init(.secondary, "Angle")]
        case .thermal:    [.init(.intensity, "Heat"), .init(.secondary, "Spread")]
        case .neon:       [.init(.intensity, "Glow"), .init(.secondary, "Hue"),
                           .init(.tertiary, "Spread")]
        case .gemSmoke:   [.init(.intensity, "Amount"), .init(.secondary, "Facets")]
        case .meshGradient:  [.init(.intensity, "Amount"), .init(.secondary, "Palette"),
                              .init(.tertiary, "Drift")]
        case .grainGradient: [.init(.intensity, "Amount"), .init(.secondary, "Grain"),
                              .init(.tertiary, "Scale")]
        case .dithering:     [.init(.intensity, "Amount"), .init(.secondary, "Colour steps"),
                              .init(.tertiary, "Scale")]
        case .flutedGlass:   [.init(.intensity, "Refraction"), .init(.secondary, "Flute width"),
                              .init(.tertiary, "Angle")]
        case .lensDistort:   [.init(.intensity, "Distort", range: -1...1),
                              .init(.secondary, "Zoom"), .init(.tertiary, "Fringing")]
        }
    }

    /// Discrete choices, offered as a segmented row (a type) or a dice (a shape).
    var variants: EffectVariants? {
        switch kind {
        case .noise:
            EffectVariants(label: "Type", names: ["Grain", "Speckle", "Static", "Colour"])
        case .meshGradient:
            // Shapes are generated, not enumerated: the dice reseeds where the colour
            // centres sit, which is the only thing that was fixed about the mesh.
            EffectVariants(label: "Shape", count: 24, isRandomised: true)
        case .dithering:
            EffectVariants(label: "Pattern", names: ["Bayer 4", "Bayer 8", "Noise"])
        default:
            nil
        }
    }
}

/// One slider on the effect panel.
struct EffectControl: Identifiable, Hashable {
    enum Slot: String, Hashable { case intensity, secondary, tertiary }

    var slot: Slot
    var label: String
    /// Bipolar controls rest at 0 and do nothing there, exactly like the interaction
    /// sliders. A lens is the obvious case: barrel one way, pincushion the other.
    var range: ClosedRange<Double>

    init(_ slot: Slot, _ label: String, range: ClosedRange<Double> = 0...1) {
        self.slot = slot
        self.label = label
        self.range = range
    }

    var isBipolar: Bool { range.lowerBound < 0 }
    var id: String { slot.rawValue }
}

/// A discrete parameter: either a named set, or a seed to roll.
struct EffectVariants: Hashable {
    var label: String
    var names: [String]?
    var count: Int
    var isRandomised: Bool

    init(label: String, names: [String]) {
        self.label = label
        self.names = names
        self.count = names.count
        self.isRandomised = false
    }

    init(label: String, count: Int, isRandomised: Bool) {
        self.label = label
        self.names = nil
        self.count = count
        self.isRandomised = isRandomised
    }
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
    /// v6 layout controls. ADDITIVE and Optional so pre-v6 files still decode; the
    /// `resolved*` accessors below supply the old behaviour as the default.
    var alignment: TextBlockAlignment?
    var letterSpacing: Double?
    var lineHeightMultiple: Double?
    /// v6, ADDITIVE and optional so compositions saved before it still decode.
    /// When set, the text is filled with this gradient across the whole block and
    /// per-glyph colours are ignored. When nil, each glyph uses its own colour, so
    /// v3's per-letter colour divergence still works.
    var textGradient: GradientPaint?
    /// v6: shaders can run on the background as well as the text block.
    var backgroundShader: ShaderEffect?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        aspectRatio: AspectRatio = .square,
        background: Background = .defaultBackground,
        globalShader: ShaderEffect = .none,
        glyphs: [Glyph] = [],
        textGradient: GradientPaint? = nil,
        backgroundShader: ShaderEffect? = nil,
        alignment: TextBlockAlignment? = nil,
        letterSpacing: Double? = nil,
        lineHeightMultiple: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.aspectRatio = aspectRatio
        self.background = background
        self.globalShader = globalShader
        self.glyphs = glyphs
        self.textGradient = textGradient
        self.backgroundShader = backgroundShader
        self.alignment = alignment
        self.letterSpacing = letterSpacing
        self.lineHeightMultiple = lineHeightMultiple
    }

    /// Defaults match pre-v6 behaviour exactly, so an old file renders identically.
    var resolvedAlignment: TextBlockAlignment { alignment ?? .center }
    var resolvedLetterSpacing: CGFloat { CGFloat(letterSpacing ?? 0) }
    var resolvedLineHeight: CGFloat { CGFloat(lineHeightMultiple ?? 1) }

    var text: String { glyphs.map(\.character).joined() }
    var isEmpty: Bool { glyphs.isEmpty }

    /// Largest glyph on the canvas — drives line spacing and empty-line height.
    var dominantSize: CGFloat { glyphs.map(\.size).max() ?? 140 }
}
