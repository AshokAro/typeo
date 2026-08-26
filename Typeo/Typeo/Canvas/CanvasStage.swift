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
    let availableSize: CGSize

    private var reference: CGSize { composition.aspectRatio.referenceSize }

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

    var body: some View {
        SpriteView(
            scene: scene,
            preferredFramesPerSecond: 60,
            options: [.ignoresSiblingOrder]
        )
        .frame(width: displaySize.width, height: displaySize.height)
        // iOS continuous curvature (squircle), not a plain circular corner.
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
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
