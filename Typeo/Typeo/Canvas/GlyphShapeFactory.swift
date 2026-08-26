//
//  GlyphShapeFactory.swift
//  Typeo
//
//  Collision proxies that follow the LETTER, not its bounding box.
//
//  A single circle per glyph made a T and an I behave identically, so letters stopped
//  well short of each other and never interlocked. Each glyph is instead rasterised
//  into a coarse coverage grid and covered with small circles, which is cheap to test,
//  rotates with the node, and is deterministic — the recorded video has to reproduce
//  the same collisions as the screen.
//

import UIKit
import CoreGraphics

/// A collision circle in the sprite's own space: x from the left edge, y from the
/// vertical centre (SKSpriteNode anchor 0, 0.5), both in unscaled points.
struct GlyphCircle: Hashable {
    var centre: CGPoint
    var radius: CGFloat
}

enum GlyphShapeFactory {

    private struct Key: Hashable {
        var character: String
        var fontName: String?
        var design: GlyphFont.SystemDesign
        var size: CGFloat
    }

    private static var cache: [Key: [GlyphCircle]] = [:]
    /// Bounded for the same reason as the texture cache: one entry per size the slider
    /// passes through.
    private static let cacheLimit = 400

    /// Rows of cells down the glyph's height. Six is enough for a stem and a crossbar
    /// to be distinct without turning a pair test into hundreds of comparisons.
    private static let rows = 6
    /// Fraction of a cell that must be inked before it becomes a circle.
    private static let inkThreshold: CGFloat = 0.28

    static func circles(for glyph: Glyph) -> [GlyphCircle] {
        guard glyph.role == .glyph else { return [] }
        let key = Key(character: glyph.character, fontName: glyph.font.fontName,
                      design: glyph.font.design, size: glyph.size)
        if let cached = cache[key] { return cached }

        let box = GlyphTextureFactory.metric(for: glyph).size
        guard box.width > 0, box.height > 0 else { return [] }

        let cell = box.height / CGFloat(rows)
        let columns = max(1, Int((box.width / cell).rounded()))

        let result = coverage(glyph: glyph, box: box, columns: columns, rows: rows)
            .map { sample -> GlyphCircle in
                GlyphCircle(
                    centre: CGPoint(
                        x: (CGFloat(sample.column) + 0.5) * box.width / CGFloat(columns),
                        // Bitmap rows run down from the top; the sprite's origin is its
                        // vertical centre with y growing up.
                        y: box.height / 2 - (CGFloat(sample.row) + 0.5) * cell
                    ),
                    // Half a cell. Any larger and the circles of ADJACENT LETTERS touch
                    // at rest, so switching collision on nudged a normally-spaced word
                    // apart before anything had moved.
                    radius: cell * 0.5
                )
            }

        let circles = result.isEmpty
            ? [GlyphCircle(centre: CGPoint(x: box.width / 2, y: 0),
                           radius: min(box.width, box.height) / 2)]
            : result
        if cache.count > cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = circles
        return circles
    }

    private struct Sample { var column: Int; var row: Int }

    /// Draws the glyph at CELL resolution, so one pixel IS one cell's ink coverage.
    /// It goes through UIGraphicsImageRenderer rather than a bare CGContext because
    /// that is what gives UIKit text drawing its flipped coordinate space; drawing
    /// straight into a raw context renders the glyph upside down.
    private static func coverage(glyph: Glyph, box: CGSize, columns: Int, rows: Int) -> [Sample] {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let font = GlyphTextureFactory.uiFont(for: glyph.font, size: glyph.size)

        let image = UIGraphicsImageRenderer(
            size: CGSize(width: columns, height: rows), format: format
        ).image { context in
            context.cgContext.scaleBy(x: CGFloat(columns) / box.width,
                                      y: CGFloat(rows) / box.height)
            (glyph.character as NSString).draw(
                at: .zero,
                withAttributes: [.font: font, .foregroundColor: UIColor.white]
            )
        }

        guard let cgImage = image.cgImage else { return [] }
        var pixels = [UInt8](repeating: 0, count: columns * rows)
        guard let context = CGContext(
            data: &pixels,
            width: columns, height: rows,
            bitsPerComponent: 8, bytesPerRow: columns,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: columns, height: rows))

        var samples: [Sample] = []
        for row in 0..<rows {
            for column in 0..<columns where CGFloat(pixels[row * columns + column]) / 255 > inkThreshold {
                samples.append(Sample(column: column, row: row))
            }
        }
        return samples
    }

    static func purge() { cache.removeAll() }
}
