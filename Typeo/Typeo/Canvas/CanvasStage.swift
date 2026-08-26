//
//  CanvasStage.swift
//  Typeo
//
//  On-screen presentation of the canvas. Scales the reference-size canvas down to fit,
//  and when an effect is active shows the SAME filtered image the exporter produces.
//

import SwiftUI

struct CanvasStage: View {
    let composition: Composition
    let availableSize: CGSize

    @State private var filtered: UIImage?
    @State private var isRendering = false

    private var reference: CGSize { composition.aspectRatio.referenceSize }

    private var displaySize: CGSize {
        let widthScale = availableSize.width / reference.width
        let heightScale = availableSize.height / reference.height
        let scale = min(widthScale, heightScale)
        return CGSize(width: reference.width * scale, height: reference.height * scale)
    }

    private var scale: CGFloat { displaySize.width / reference.width }

    var body: some View {
        Group {
            if composition.globalShader.kind == .none {
                liveCanvas
            } else if let filtered {
                Image(uiImage: filtered)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displaySize.width, height: displaySize.height)
            } else {
                liveCanvas
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(.rect(cornerRadius: 4))
        .task(id: composition) {
            await refreshFilteredPreview()
        }
    }

    private var liveCanvas: some View {
        CompositionCanvas(composition: composition)
            .frame(width: reference.width, height: reference.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
    }

    private func refreshFilteredPreview() async {
        guard composition.globalShader.kind != .none else {
            filtered = nil
            return
        }
        // Debounce: typing should not trigger a Core Image pass per keystroke.
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }
        filtered = CompositionRenderer.render(composition, scale: 1)
    }
}
