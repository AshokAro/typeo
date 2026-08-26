//
//  CanvasStage.swift
//  Typeo
//
//  On-screen presentation. Scales the reference-size canvas down to fit and drives
//  the animation clock for time-based shaders. No snapshotting: the shaders run live
//  on the GPU and ImageRenderer captures the same modifiers at export.
//

import SwiftUI

struct CanvasStage: View {
    let composition: Composition
    let availableSize: CGSize
    /// Shared with the editor so an exported frame matches what is on screen.
    let animationStart: Date

    private var reference: CGSize { composition.aspectRatio.referenceSize }

    private var displaySize: CGSize {
        let scale = min(
            availableSize.width / reference.width,
            availableSize.height / reference.height
        )
        return CGSize(width: reference.width * scale, height: reference.height * scale)
    }

    private var scale: CGFloat { displaySize.width / reference.width }

    var body: some View {
        Group {
            if composition.globalShader.kind.isAnimated {
                TimelineView(.animation) { timeline in
                    canvas(at: timeline.date.timeIntervalSince(animationStart))
                }
            } else {
                canvas(at: 0)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(.rect(cornerRadius: 4))
    }

    private func canvas(at time: Double) -> some View {
        CompositionCanvas(composition: composition, time: time)
            .frame(width: reference.width, height: reference.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
    }
}
