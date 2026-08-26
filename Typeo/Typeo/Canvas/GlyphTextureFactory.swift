//
//  GlyphTextureFactory.swift
//  Typeo
//
//  Renders each glyph with UIKit and hands SpriteKit a texture.
//
//  Why not SKLabelNode: it silently falls back to Times when given the system font's
//  PostScript name (".SFUI-Semibold"), which would break the four system entries in
//  FontCatalog and change how v2-era saved compositions look. Rendering through
//  UIFont keeps metrics identical to v1/v2.
//
//  Glyphs are drawn WHITE into a box the height of the font's line height, sitting on
//  the baseline. Baselines therefore align across mixed fonts and sizes on one line,
//  and colour is applied by tinting the sprite rather than re-rendering.
//

import UIKit
import SpriteKit

enum GlyphTextureFactory {

    private struct Key: Hashable {
        var character: String
        var fontName: String?
        var design: GlyphFont.SystemDesign
        var size: CGFloat
    }

    private static var cache: [Key: SKTexture] = [:]
    private static var sizes: [Key: CGSize] = [:]

    /// Dragging the size slider mints a texture per step — 190 of them across the
    /// range, per character. Unbounded, that is tens of megabytes of glyphs nobody is
    /// looking at any more, so the cache is emptied rather than allowed to grow.
    private static let cacheLimit = 240

    private static func trimIfNeeded() {
        guard cache.count > cacheLimit else { return }
        cache.removeAll(keepingCapacity: true)
        sizes.removeAll(keepingCapacity: true)
    }

    static func uiFont(for font: GlyphFont, size: CGFloat) -> UIFont {
        if let name = font.fontName, let custom = UIFont(name: name, size: size) {
            return custom
        }
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        let design: UIFontDescriptor.SystemDesign = switch font.design {
        case .standard:   .default
        case .rounded:    .rounded
        case .serif:      .serif
        case .monospaced: .monospaced
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Box size for a glyph: advance width by full line height.
    static func metric(for glyph: Glyph) -> GlyphMetric {
        let key = Key(character: glyph.character, fontName: glyph.font.fontName,
                      design: glyph.font.design, size: glyph.size)
        if let cached = sizes[key] {
            return GlyphMetric(size: cached, role: glyph.role)
        }
        let font = uiFont(for: glyph.font, size: glyph.size)
        let advance = (glyph.character as NSString)
            .size(withAttributes: [.font: font]).width
        let size = CGSize(width: ceil(advance), height: ceil(font.lineHeight))
        sizes[key] = size
        return GlyphMetric(size: size, role: glyph.role)
    }

    /// White texture for the glyph. Returns nil for whitespace and line breaks.
    static func texture(for glyph: Glyph) -> SKTexture? {
        guard glyph.role == .glyph else { return nil }

        let key = Key(character: glyph.character, fontName: glyph.font.fontName,
                      design: glyph.font.design, size: glyph.size)
        if let cached = cache[key] { return cached }

        let font = uiFont(for: glyph.font, size: glyph.size)
        let box = metric(for: glyph).size
        guard box.width > 0, box.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1          // box is already in 1080-reference points
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: box, format: format).image { _ in
            (glyph.character as NSString).draw(
                at: CGPoint(x: 0, y: 0),
                withAttributes: [.font: font, .foregroundColor: UIColor.white]
            )
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        trimIfNeeded()
        return texture
    }

    static func purge() {
        cache.removeAll()
        sizes.removeAll()
    }

    #if DEBUG
    static var debugCacheCount: Int { cache.count }
    #endif
}
