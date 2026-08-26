//
//  FontCatalog.swift
//  Typeo
//
//  v1 ships system faces only — no bundled files, no licence checks. Bundling OFL
//  faces is a v2 concern (see CLAUDE.md conventions).
//

import SwiftUI
import UIKit

struct FontOption: Identifiable, Hashable {
    var displayName: String
    var fontName: String?
    var design: GlyphFont.SystemDesign

    var id: String { fontName ?? "system.\(design.rawValue)" }
    var glyphFont: GlyphFont { GlyphFont(fontName: fontName, design: design) }
}

enum FontCatalog {

    /// Curated, deliberately opinionated. Anything unavailable on the running OS is
    /// filtered out rather than silently falling back to Helvetica.
    static let all: [FontOption] = {
        let system: [FontOption] = [
            FontOption(displayName: "System",     fontName: nil, design: .standard),
            FontOption(displayName: "Rounded",    fontName: nil, design: .rounded),
            FontOption(displayName: "Serif",      fontName: nil, design: .serif),
            FontOption(displayName: "Monospaced", fontName: nil, design: .monospaced),
        ]

        let candidates: [(String, String)] = [
            ("Futura",              "Futura-Bold"),
            ("Didot",               "Didot-Bold"),
            ("Bodoni 72",           "BodoniSvtyTwoITCTT-Bold"),
            ("Baskerville",         "Baskerville-Bold"),
            ("Georgia",             "Georgia-Bold"),
            ("Palatino",            "Palatino-Bold"),
            ("Optima",              "Optima-Bold"),
            ("Avenir Next",         "AvenirNext-Bold"),
            ("Helvetica Neue",      "HelveticaNeue-Bold"),
            ("American Typewriter", "AmericanTypewriter-Bold"),
            ("Copperplate",         "Copperplate-Bold"),
            ("Marker Felt",         "MarkerFelt-Wide"),
            ("Chalkduster",         "Chalkduster"),
            ("Snell Roundhand",     "SnellRoundhand-Black"),
            ("Party LET",           "PartyLetPlain"),
            ("Zapfino",             "Zapfino"),
        ]

        let available = candidates
            .filter { UIFont(name: $0.1, size: 12) != nil }
            .map { FontOption(displayName: $0.0, fontName: $0.1, design: .standard) }

        return system + available
    }()

    static func option(matching font: GlyphFont) -> FontOption? {
        all.first { $0.glyphFont == font }
    }
}
