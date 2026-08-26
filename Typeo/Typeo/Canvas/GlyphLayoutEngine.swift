//
//  GlyphLayoutEngine.swift
//  Typeo
//
//  Renderer-agnostic line breaking. Extracted from v1's SwiftUI Layout so the
//  SpriteKit canvas wraps text exactly the way v1 and v2 did — compositions saved
//  before v3 must not reflow when reopened.
//
//  Coordinates are top-left origin. SpriteKit flips them at placement time.
//

import CoreGraphics

struct GlyphMetric {
    var size: CGSize
    var role: GlyphRole
}

struct GlyphPlacement {
    var index: Int
    /// Leading edge, vertically centred on the line, in top-left origin space.
    var position: CGPoint
    var size: CGSize
}

struct GlyphBlockLayout {
    var placements: [GlyphPlacement]
    var size: CGSize
}

enum GlyphLayoutEngine {

    struct Line {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    static func layout(
        metrics: [GlyphMetric],
        maxWidth: CGFloat,
        lineSpacing: CGFloat,
        fallbackLineHeight: CGFloat,
        letterSpacing: CGFloat = 0,
        alignment: TextBlockAlignment = .center
    ) -> GlyphBlockLayout {
        let lines = wrap(
            metrics: metrics,
            maxWidth: maxWidth,
            fallbackLineHeight: fallbackLineHeight,
            letterSpacing: letterSpacing
        )
        guard !lines.isEmpty else { return GlyphBlockLayout(placements: [], size: .zero) }

        let blockWidth = lines.map(\.width).max() ?? 0
        let blockHeight = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(lines.count - 1)

        var placements: [GlyphPlacement] = []
        var y: CGFloat = 0

        for line in lines {
            var x: CGFloat = switch alignment {
            case .leading:  0
            case .center:   (blockWidth - line.width) / 2
            case .trailing: blockWidth - line.width
            }
            for index in line.indices {
                let size = metrics[index].size
                placements.append(
                    GlyphPlacement(
                        index: index,
                        position: CGPoint(x: x, y: y + line.height / 2),
                        size: size
                    )
                )
                x += size.width + letterSpacing
            }
            y += line.height + lineSpacing
        }

        return GlyphBlockLayout(
            placements: placements,
            size: CGSize(width: blockWidth, height: blockHeight)
        )
    }

    static func wrap(
        metrics: [GlyphMetric],
        maxWidth: CGFloat,
        fallbackLineHeight: CGFloat,
        letterSpacing: CGFloat = 0
    ) -> [Line] {
        var lines: [Line] = []
        var current: [Int] = []
        var lastSpaceSlot: Int?

        func width(of indices: [Int]) -> CGFloat {
            guard !indices.isEmpty else { return 0 }
            let glyphs = indices.reduce(0) { $0 + metrics[$1].size.width }
            return glyphs + letterSpacing * CGFloat(indices.count - 1)
        }
        func height(of indices: [Int]) -> CGFloat {
            let tallest = indices.map { metrics[$0].size.height }.max() ?? 0
            return tallest > 0 ? tallest : fallbackLineHeight
        }
        func flush(_ indices: [Int]) {
            lines.append(Line(indices: indices, width: width(of: indices), height: height(of: indices)))
        }

        for index in metrics.indices {
            let metric = metrics[index]

            if metric.role == .lineBreak {
                flush(current)
                current = []
                lastSpaceSlot = nil
                continue
            }

            if !current.isEmpty, width(of: current) + metric.size.width > maxWidth {
                if let slot = lastSpaceSlot, slot > 0, slot < current.count - 1 {
                    let head = Array(current[..<slot])
                    let tail = Array(current[(slot + 1)...])
                    flush(head)
                    current = tail
                } else {
                    flush(current)
                    current = []
                }
                lastSpaceSlot = nil
            }

            current.append(index)
            if metric.role == .space { lastSpaceSlot = current.count - 1 }
        }

        if !current.isEmpty || lines.isEmpty {
            flush(current)
        }
        return lines
    }
}
