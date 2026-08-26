//
//  GlyphScene.swift
//  Typeo
//
//  v3: the canvas is now individually addressable glyph nodes.
//
//  Each Glyph in the model becomes one SKSpriteNode. Interaction moves the NODES;
//  `syncToComposition` writes the result back into each Glyph's positionOffset and
//  rotation — the two fields that have existed unused since v1. The model does not
//  move; the UI simply stops writing the same value to every glyph.
//

import SpriteKit
import SwiftUI
import UIKit
import simd

enum GlyphInteraction: String, CaseIterable, Identifiable {
    case none, inflate, float, gravity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:    "Off"
        case .inflate: "Inflate"
        case .float:   "Float"
        case .gravity: "Drop"
        }
    }

    var systemImage: String {
        switch self {
        case .none:    "hand.raised.slash"
        case .inflate: "arrow.up.left.and.arrow.down.right"
        case .float:   "wind"
        case .gravity: "arrow.down.to.line"
        }
    }
}

final class GlyphScene: SKScene {

    private(set) var composition: Composition
    var interaction: GlyphInteraction = .none

    private var glyphNodes: [UUID: SKSpriteNode] = [:]
    private var restPositions: [UUID: CGPoint] = [:]
    private var effectNode = SKEffectNode()   // outer: the FX shader
    private var fillNode = SKEffectNode()     // inner: the text gradient fill
    private var backgroundNode = SKSpriteNode()
    private var touchPoint: CGPoint?
    private var isHolding = false

    /// Fraction of canvas width the text block may occupy — matches v1/v2.
    private let textInset: CGFloat = 0.88

    init(composition: Composition, size: CGSize) {
        self.composition = composition
        super.init(size: size)
        scaleMode = .aspectFill
        anchorPoint = .zero
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        rebuild()
    }

    // MARK: - Building

    func update(composition: Composition) {
        let needsRebuild = composition.glyphs.map(\.id) != self.composition.glyphs.map(\.id)
            || composition.glyphs.map(\.size) != self.composition.glyphs.map(\.size)
            || composition.glyphs.map(\.font) != self.composition.glyphs.map(\.font)
            || composition.aspectRatio != self.composition.aspectRatio
        self.composition = composition
        if needsRebuild {
            rebuild()
        } else {
            applyAppearance()
        }
    }

    func rebuild() {
        removeAllChildren()
        glyphNodes.removeAll()
        restPositions.removeAll()

        size = composition.aspectRatio.referenceSize

        backgroundNode = BackgroundTextureFactory.node(for: composition.background, size: size)
        backgroundNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundNode.zPosition = -10
        addChild(backgroundNode)

        effectNode = SKEffectNode()
        effectNode.shouldEnableEffects = composition.globalShader.kind != .none
        effectNode.shouldRasterize = false
        effectNode.zPosition = 0
        addChild(effectNode)

        // A clear sprite the size of the canvas keeps the effect node's raster large
        // enough that a glow or tear is not clipped at the text block's edge.
        let bleed = SKSpriteNode(color: .clear, size: size)
        bleed.position = CGPoint(x: size.width / 2, y: size.height / 2)
        bleed.alpha = 0.001
        effectNode.addChild(bleed)

        // One SKEffectNode cannot stack two shaders, so the gradient fill gets its own
        // node INSIDE the FX node: fill is applied to the glyphs, then FX runs over it.
        fillNode = SKEffectNode()
        fillNode.shouldRasterize = false
        effectNode.addChild(fillNode)

        let metrics = composition.glyphs.map { GlyphTextureFactory.metric(for: $0) }
        let dominant = composition.dominantSize
        let layout = GlyphLayoutEngine.layout(
            metrics: metrics,
            maxWidth: size.width * textInset,
            lineSpacing: dominant * 0.14,
            fallbackLineHeight: dominant * 0.9
        )

        let originX = (size.width - layout.size.width) / 2
        let originY = (size.height - layout.size.height) / 2

        for placement in layout.placements {
            let glyph = composition.glyphs[placement.index]
            guard let texture = GlyphTextureFactory.texture(for: glyph) else { continue }

            let node = SKSpriteNode(texture: texture)
            node.size = placement.size
            node.anchorPoint = CGPoint(x: 0, y: 0.5)
            node.color = UIColor(glyph.color.color)
            node.colorBlendFactor = 1

            // Top-left origin layout -> SpriteKit's bottom-left origin.
            let rest = CGPoint(
                x: originX + placement.position.x,
                y: size.height - originY - placement.position.y
            )
            restPositions[glyph.id] = rest
            node.position = CGPoint(
                x: rest.x + glyph.positionOffset.x,
                y: rest.y - glyph.positionOffset.y
            )
            node.zRotation = -glyph.rotation * .pi / 180

            glyphNodes[glyph.id] = node
            fillNode.addChild(node)
        }

        applyShader()
    }

    private func applyAppearance() {
        for glyph in composition.glyphs {
            guard let node = glyphNodes[glyph.id] else { continue }
            node.color = UIColor(glyph.color.color)
            node.colorBlendFactor = 1
        }
        effectNode.shouldEnableEffects = composition.globalShader.kind != .none
        applyShader()
    }

    private func applyFill() {
        guard let gradient = composition.textGradient else {
            fillNode.shader = nil
            fillNode.shouldEnableEffects = false
            return
        }
        fillNode.shader = SpriteShaders.gradientFillShader(gradient)
        fillNode.shouldEnableEffects = true
    }

    private func applyShader() {
        applyFill()
        guard let shader = SpriteShaders.shader(for: composition.globalShader) else {
            effectNode.shader = nil
            effectNode.shouldEnableEffects = false
            return
        }
        shader.uniformNamed("u_texel")?.vectorFloat2Value = vector_float2(
            Float(1.0 / size.width), Float(1.0 / size.height)
        )
        effectNode.shader = shader
        effectNode.shouldEnableEffects = true
    }

    // MARK: - Motion
    //
    // Motion is integrated by hand rather than with SKPhysicsBody.
    //
    // SKRenderer, which the offscreen video exporter uses, does NOT step the scene
    // once per render call — measured at 2 scene updates across 60 renders — so
    // SpriteKit's own simulation barely advances during a recording while it runs
    // normally in a live SKView. That would make a recorded drop differ from the drop
    // on screen. Integrating here, driven by an explicit `advance(to:)`, keeps the
    // live canvas and the exported video identical, which is the whole point.

    private struct Motion {
        var velocity: CGFloat = 0
        var spin: CGFloat = 0
    }

    private var motion: [UUID: Motion] = [:]
    private var interactionStart: TimeInterval?
    private var lastAdvance: TimeInterval?

    /// Deterministic per-frame step. Called by the live scene's update and by the
    /// offscreen frame renderer, so both produce the same animation.
    func advance(to time: TimeInterval) {
        if interactionStart == nil { interactionStart = time }
        let elapsed = time - (interactionStart ?? time)
        let delta = min(1.0 / 20.0, max(0, time - (lastAdvance ?? time)))
        lastAdvance = time

        switch interaction {
        case .none:
            break

        case .inflate:
            guard isHolding, let touch = touchPoint else { break }
            let reach = size.width * 0.35
            for node in glyphNodes.values {
                let centre = CGPoint(x: node.position.x + node.size.width / 2, y: node.position.y)
                let distance = hypot(centre.x - touch.x, centre.y - touch.y)
                let influence = max(0, 1 - distance / reach)
                let target = 1 + influence * 1.6
                let rate = min(1, delta * 8)
                node.setScale(node.xScale + (target - node.xScale) * rate)
            }

        case .float:
            guard isHolding else { break }
            for (id, node) in glyphNodes {
                guard let rest = restPositions[id] else { continue }
                let seed = seedValue(for: id)
                let drift = sin(elapsed * 1.6 + seed * 6.28) * 16
                let rise = min(size.height * 0.24, elapsed * size.height * 0.14)
                node.position = CGPoint(x: rest.x + drift, y: rest.y + rise)
                node.zRotation = CGFloat(sin(elapsed * 1.1 + seed * 6.28) * 0.12)
            }

        case .gravity:
            guard delta > 0 else { break }
            let gravity = -size.height * 2.4          // points per second squared
            let bounce: CGFloat = 0.32
            for (id, node) in glyphNodes {
                var state = motion[id] ?? Motion(velocity: 0, spin: (seedValue(for: id) - 0.5) * 3.2)
                state.velocity += gravity * delta
                node.position.y += state.velocity * delta
                node.zRotation += state.spin * delta

                let floor = node.size.height / 2
                if node.position.y <= floor {
                    node.position.y = floor
                    state.velocity = -state.velocity * bounce
                    state.spin *= 0.45
                    if abs(state.velocity) < size.height * 0.06 {
                        state.velocity = 0
                        state.spin = 0
                    }
                }
                motion[id] = state
            }
        }
    }

    private func seedValue(for id: UUID) -> CGFloat {
        CGFloat(abs(id.uuidString.hashValue % 1000)) / 1000
    }

    private func resetMotion() {
        motion.removeAll()
        interactionStart = nil
        lastAdvance = nil
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        touchPoint = point
        isHolding = true
        resetMotion()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchPoint = touches.first?.location(in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHolding = false
        touchPoint = nil
        if interaction != .gravity { springBack() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func springBack() {
        for (id, node) in glyphNodes {
            guard let rest = restPositions[id] else { continue }
            node.removeAllActions()
            node.run(.group([
                .move(to: rest, duration: 0.45),
                .scale(to: 1, duration: 0.45),
            ]))
        }
    }

    /// Restores every glyph to its laid-out position and clears any motion.
    func reset() {
        resetMotion()
        for (id, node) in glyphNodes {
            guard let rest = restPositions[id] else { continue }
            node.removeAllActions()
            node.run(.group([
                .move(to: rest, duration: 0.4),
                .scale(to: 1, duration: 0.4),
                .rotate(toAngle: 0, duration: 0.4, shortestUnitArc: true),
            ]))
        }
    }

    // MARK: - Per-frame

    override func update(_ currentTime: TimeInterval) {
        advance(to: currentTime)
    }

    /// Starts the current interaction without a touch, so an offscreen recording can
    /// drive it. v4 uses this to capture a drop or a float.
    func beginAutomaticInteraction() {
        guard interaction != .none else { return }
        resetMotion()
        isHolding = true
        touchPoint = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Writing back to the model

    /// Current node state expressed as per-glyph offsets, ready to store on the model.
    func glyphTransforms() -> [UUID: (offset: CGPoint, rotation: Double)] {
        var result: [UUID: (CGPoint, Double)] = [:]
        for (id, node) in glyphNodes {
            guard let rest = restPositions[id] else { continue }
            let offset = CGPoint(x: node.position.x - rest.x, y: rest.y - node.position.y)
            let degrees = Double(-node.zRotation) * 180 / .pi
            result[id] = (offset, degrees)
        }
        return result
    }
}

// MARK: - Background

enum BackgroundTextureFactory {
    static func node(for background: Background, size: CGSize) -> SKSpriteNode {
        switch background {
        case let .solid(rgba):
            return SKSpriteNode(color: UIColor(rgba.color), size: size)

        case let .linearGradient(colors, angleDegrees):
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                let cgColors = colors.map { UIColor($0.color).cgColor } as CFArray
                guard let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: cgColors,
                    locations: nil
                ) else { return }
                let radians = angleDegrees * .pi / 180
                let start = CGPoint(x: size.width * (0.5 - 0.5 * cos(radians)),
                                    y: size.height * (0.5 - 0.5 * sin(radians)))
                let end = CGPoint(x: size.width * (0.5 + 0.5 * cos(radians)),
                                  y: size.height * (0.5 + 0.5 * sin(radians)))
                // Without these, anything outside the start/end band is left unpainted
                // and the canvas corners come out black at any oblique angle.
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: start,
                    end: end,
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            return SKSpriteNode(texture: SKTexture(image: image), size: size)
        }
    }
}
