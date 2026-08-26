//
//  CanvasStage.swift
//  Typeo
//
//  On-screen presentation of the v3 SpriteKit canvas, scaled from the reference size
//  to fit the available space. The scene is owned by the editor so it can read node
//  transforms back out before an export or a save.
//

import SwiftUI
import SpriteKit

struct CanvasStage: View {
    let scene: GlyphScene
    let composition: Composition
    let interaction: GlyphInteraction
    let interactionAmount: Double
    var collisions: Bool = false
    /// Drawn INSIDE the canvas, so it moves and scales with it like anything else on
    /// the artboard.
    var showsEmptyHint: Bool = false
    let availableSize: CGSize

    private var reference: CGSize { composition.aspectRatio.referenceSize }

    /// How far the reference canvas is scaled down to fit the screen. Everything drawn
    /// over the canvas is sized in REFERENCE points and multiplied by this, which is the
    /// same rule the canvas itself follows.
    private var displayScale: CGFloat { displaySize.width / reference.width }

    private var displaySize: CGSize {
        let scale = min(
            availableSize.width / reference.width,
            availableSize.height / reference.height
        )
        return CGSize(
            width: max(1, reference.width * scale),
            height: max(1, reference.height * scale)
        )
    }

    /// Sized in reference points and scaled like the canvas, rather than sitting at a
    /// fixed size over it — at 9:16, or with a sheet open, a fixed hint was the wrong
    /// size and in the wrong place.
    private var emptyHint: some View {
        // Floored: 16:9 scales the canvas down far enough that a strictly proportional
        // hint stops being readable, and it is an instruction rather than artwork.
        let hintScale = max(displayScale, 0.24)
        return VStack(spacing: 24 * hintScale) {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 78 * hintScale, weight: .light))
            Text("Tap the canvas to type")
                .font(.system(size: 46 * hintScale, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white.opacity(0.35))
        .padding(.horizontal, 40 * hintScale)
        .allowsHitTesting(false)
    }

    var body: some View {
        SpriteView(
            scene: scene,
            preferredFramesPerSecond: 60,
            options: [.ignoresSiblingOrder]
        )
        .frame(width: displaySize.width, height: displaySize.height)
        // iOS continuous curvature (squircle), not a plain circular corner.
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .overlay {
            if showsEmptyHint { emptyHint }
        }
        .onAppear {
            scene.interaction = interaction
            scene.interactionAmount = interactionAmount
            scene.collisionsEnabled = collisions
            scene.update(composition: composition)
        }
        .onChange(of: composition) { _, new in
            scene.update(composition: new)
        }
        .onChange(of: interaction) { _, new in
            scene.interaction = new
        }
        .onChange(of: interactionAmount) { _, new in
            scene.interactionAmount = new
        }
        .onChange(of: collisions) { _, new in
            scene.collisionsEnabled = new
        }
    }
}
