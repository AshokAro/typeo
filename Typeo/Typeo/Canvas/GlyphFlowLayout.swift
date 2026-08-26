//
//  GlyphFlowLayout.swift
//  Typeo
//
//  Lays out individually-addressable glyph views with word-aware wrapping.
//  This is deliberately NOT a `Text` view: v3 needs every glyph to be its own
//  positioned node, so v1 pays that cost up front.
//

import SwiftUI

nonisolated struct GlyphRoleKey: LayoutValueKey {
    static let defaultValue: GlyphRole = .glyph
}

nonisolated struct GlyphFlowLayout: Layout {
    var lineSpacing: CGFloat = 0
    /// Height used for a line that contains no glyphs (e.g. a blank line from Return).
    var fallbackLineHeight: CGFloat = 40

    struct Line {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let metrics = measure(subviews)
        let lines = wrap(metrics: metrics, maxWidth: maxWidth)
        guard !lines.isEmpty else { return .zero }

        let naturalWidth = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(lines.count - 1)
        // Report the PROPOSED width, not the natural one. placeSubviews receives these
        // bounds and re-wraps against them, so the two passes must agree on max width
        // or the line breaks (and therefore the height) diverge.
        return CGSize(width: maxWidth.isFinite ? maxWidth : naturalWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let metrics = measure(subviews)
        let lines = wrap(metrics: metrics, maxWidth: bounds.width)

        var placed = Set<Int>()
        var y = bounds.minY

        for line in lines {
            var x = bounds.midX - line.width / 2
            for index in line.indices {
                let size = metrics[index].size
                subviews[index].place(
                    at: CGPoint(x: x, y: y + line.height / 2),
                    anchor: .leading,
                    proposal: ProposedViewSize(size)
                )
                placed.insert(index)
                x += size.width
            }
            y += line.height + lineSpacing
        }

        // Line-break glyphs are never part of a line — place them with zero size so
        // SwiftUI does not leave them unplaced.
        for index in subviews.indices where !placed.contains(index) {
            subviews[index].place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
        }
    }

    // MARK: - Measurement and wrapping

    private struct Metric {
        var size: CGSize
        var role: GlyphRole
    }

    private func measure(_ subviews: Subviews) -> [Metric] {
        subviews.map { subview in
            Metric(size: subview.sizeThatFits(.unspecified), role: subview[GlyphRoleKey.self])
        }
    }

    private func wrap(metrics: [Metric], maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current: [Int] = []
        var lastSpaceSlot: Int?

        func width(of indices: [Int]) -> CGFloat {
            indices.reduce(0) { $0 + metrics[$1].size.width }
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
                    // Break at the last space: the space itself is dropped, the
                    // partial word travels to the next line.
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

        // A trailing Return does not add a visible line; interior blank lines survive
        // because they were flushed when their line break was encountered.
        if !current.isEmpty || lines.isEmpty {
            flush(current)
        }
        return lines
    }
}
