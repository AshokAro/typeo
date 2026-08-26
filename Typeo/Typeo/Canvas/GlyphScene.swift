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
    private var effectNode = SKEffectNode()
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
        physicsWorld.gravity = .zero
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
            effectNode.addChild(node)
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

    private func applyShader() {
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

    // MARK: - Physics setup

    private func enablePhysics(_ enabled: Bool) {
        if enabled {
            physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
            physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: size))
            for node in glyphNodes.values where node.physicsBody == nil {
                let body = SKPhysicsBody(rectangleOf: node.size,
                                         center: CGPoint(x: node.size.width / 2, y: 0))
                body.restitution = 0.35
                body.friction = 0.6
                body.linearDamping = 0.2
                body.angularDamping = 0.4
                body.allowsRotation = true
                node.physicsBody = body
            }
        } else {
            physicsWorld.gravity = .zero
            physicsBody = nil
            for node in glyphNodes.values { node.physicsBody = nil }
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        touchPoint = point
        isHolding = true
        if interaction == .gravity { enablePhysics(true) }
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

    /// Restores every glyph to its laid-out position and clears physics.
    func reset() {
        enablePhysics(false)
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
                node.setScale(node.xScale + (target - node.xScale) * 0.25)
            }

        case .float:
            guard isHolding else { break }
            for (id, node) in glyphNodes {
                guard let rest = restPositions[id] else { continue }
                let seed = CGFloat(abs(id.hashValue % 1000)) / 1000
                let drift = sin(currentTime * 1.6 + seed * 6.28) * 14
                let rise = min(size.height * 0.22, (node.position.y - rest.y) + 2.4)
                node.position = CGPoint(x: rest.x + drift, y: rest.y + rise)
                node.zRotation = sin(currentTime * 1.1 + seed * 6.28) * 0.12
            }

        case .gravity:
            break   // SKPhysicsBody drives it
        }
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
                context.cgContext.drawLinearGradient(gradient, start: start, end: end, options: [])
            }
            return SKSpriteNode(texture: SKTexture(image: image), size: size)
        }
    }
}
