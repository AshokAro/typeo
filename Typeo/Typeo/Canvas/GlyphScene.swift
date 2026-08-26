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
import CoreImage
import simd

final class GlyphScene: SKScene {

    private(set) var composition: Composition
    var interaction: GlyphInteraction = .none
    /// Meaning depends on the mode: bloat/pucker size, attract pull (0 = zero-g),
    /// drop gravity.
    var interactionAmount: Double = 0
    /// When locked, releasing a touch does NOT spring the letters back, so a state can
    /// be held still for a screenshot or an export.
    var isLocked = false
    /// Letters behave as solid bodies: they push each other out of the way instead of
    /// passing through. Hand-integrated, like every other motion here.
    var collisionsEnabled = false

    /// Which way is downhill, from the device. Set live by the editor and from the
    /// recorded track during an offscreen render, so a recording reproduces the same
    /// slide. Zero means the phone is in the pose it was levelled at.
    var tilt: CGVector = .zero {
        didSet { applyParallax() }
    }

    /// How far the background slides against the tilt, as a fraction of the canvas.
    private let parallaxReach: CGFloat = 0.045
    private var didReportTilt = false

    /// Called when the canvas is tapped with no interaction mode active, so the editor
    /// can move the insertion point. Carries the caret index the tap landed on.
    var onCaretTap: ((Int) -> Void)?

    /// Fired the moment an active mode starts moving letters, so the editor can light
    /// up Reset. The scene is not observable, so it has to say so rather than be asked.
    var onInteractionBegan: (() -> Void)?

    private var glyphNodes: [UUID: SKSpriteNode] = [:]
    /// Laid-out order. Collision pairs are walked over THIS, not over the node
    /// dictionary: resolving in hash order would make an offscreen recording diverge
    /// from the same touches on the live canvas.
    private var orderedIds: [UUID] = []
    private var restPositions: [UUID: CGPoint] = [:]
    /// Collision proxies that follow each letter's shape, in sprite-local points.
    private var glyphShapes: [UUID: [GlyphCircle]] = [:]
    /// Radius of the circle enclosing a glyph's whole shape, for the broad phase.
    private var glyphBounds: [UUID: CGFloat] = [:]
    /// The per-glyph transform last pushed from the model. Only a CHANGE is written to
    /// the nodes: re-applying on every appearance update would snap a held drop back
    /// to the grid the moment an unrelated colour changed.
    private var appliedTransforms: [UUID: (offset: CGPoint, rotation: Double)] = [:]
    private var fieldEffect = SKEffectNode()  // blurred copies of the glyphs, below
    private var fieldNodes: [UUID: SKSpriteNode] = [:]
    private var effectNode = SKEffectNode()   // outer: the FX shader
    private var fillNode = SKEffectNode()     // inner: the text gradient fill
    private var backgroundNode = SKSpriteNode()
    private var backgroundEffect = SKEffectNode()   // its own shader, independent of the text
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
            || composition.alignment != self.composition.alignment
            || composition.letterSpacing != self.composition.letterSpacing
            || composition.lineHeightMultiple != self.composition.lineHeightMultiple
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
        fieldNodes.removeAll()
        orderedIds.removeAll()
        glyphShapes.removeAll()
        glyphBounds.removeAll()
        restPositions.removeAll()
        appliedTransforms.removeAll()

        size = composition.aspectRatio.referenceSize

        backgroundEffect = SKEffectNode()
        backgroundEffect.zPosition = -10
        backgroundEffect.shouldRasterize = false
        addChild(backgroundEffect)

        backgroundNode = BackgroundTextureFactory.node(for: composition.background, size: size)
        // Oversized: the parallax shift would otherwise pull a bare edge into view.
        backgroundNode.size = CGSize(width: size.width * (1 + parallaxReach * 2.4),
                                     height: size.height * (1 + parallaxReach * 2.4))
        backgroundEffect.addChild(backgroundNode)
        applyParallax()

        // Glow and heat need a soft field around the letters. One shader pass cannot
        // blur, so the field is a second layer of glyph COPIES under the crisp text,
        // carrying a real CIGaussianBlur.
        fieldEffect = SKEffectNode()
        fieldEffect.zPosition = -5
        fieldEffect.shouldRasterize = false
        addChild(fieldEffect)

        let fieldBleed = SKSpriteNode(color: .clear, size: size)
        fieldBleed.position = CGPoint(x: size.width / 2, y: size.height / 2)
        fieldBleed.alpha = 0.001
        fieldEffect.addChild(fieldBleed)

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
            lineSpacing: dominant * (0.14 + (composition.resolvedLineHeight - 1)),
            fallbackLineHeight: dominant * 0.9,
            letterSpacing: composition.resolvedLetterSpacing,
            alignment: composition.resolvedAlignment
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
            appliedTransforms[glyph.id] = (offset: glyph.positionOffset, rotation: glyph.rotation)

            glyphNodes[glyph.id] = node
            orderedIds.append(glyph.id)
            let shape = GlyphShapeFactory.circles(for: glyph)
            glyphShapes[glyph.id] = shape
            glyphBounds[glyph.id] = shape.reduce(0) {
                max($0, hypot($1.centre.x - node.size.width / 2, $1.centre.y) + $1.radius)
            }
            fillNode.addChild(node)

            // The field copy is always white: the field shader colours it, so a text
            // colour change never has to touch this layer.
            let mirror = SKSpriteNode(texture: texture)
            mirror.size = node.size
            mirror.anchorPoint = node.anchorPoint
            mirror.position = node.position
            mirror.zRotation = node.zRotation
            fieldNodes[glyph.id] = mirror
            fieldEffect.addChild(mirror)
        }

        applyShader()
        syncFieldNodes()
        rebuildCaret()
    }

    private func applyAppearance() {
        // Background lives on its own node, so it has to be refreshed here too —
        // otherwise a colour change only appeared the next time something forced a
        // full rebuild.
        backgroundNode.removeFromParent()
        backgroundNode = BackgroundTextureFactory.node(for: composition.background, size: size)
        // Oversized: the parallax shift would otherwise pull a bare edge into view.
        backgroundNode.size = CGSize(width: size.width * (1 + parallaxReach * 2.4),
                                     height: size.height * (1 + parallaxReach * 2.4))
        backgroundEffect.addChild(backgroundNode)
        applyParallax()

        for glyph in composition.glyphs {
            guard let node = glyphNodes[glyph.id] else { continue }
            node.color = UIColor(glyph.color.color)
            node.colorBlendFactor = 1
        }
        applyModelTransforms()
        effectNode.shouldEnableEffects = composition.globalShader.kind != .none
        applyShader()
        syncFieldNodes()
    }

    /// Pushes positionOffset and rotation onto the nodes. Without this a shuffle that
    /// only scatters — no font or size change — could not reach the screen at all,
    /// because nothing else in the update path touches a node's transform.
    private func applyModelTransforms() {
        for glyph in composition.glyphs {
            guard let node = glyphNodes[glyph.id], let rest = restPositions[glyph.id] else { continue }
            let wanted = (offset: glyph.positionOffset, rotation: glyph.rotation)
            if let applied = appliedTransforms[glyph.id],
               applied.offset == wanted.offset,
               applied.rotation == wanted.rotation { continue }

            node.removeAllActions()
            node.position = CGPoint(x: rest.x + wanted.offset.x, y: rest.y - wanted.offset.y)
            node.zRotation = -wanted.rotation * .pi / 180
            appliedTransforms[glyph.id] = wanted
        }
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

    private func applyBackgroundShader() {
        guard let effect = composition.backgroundShader,
              let shader = SpriteShaders.shader(for: effect) else {
            backgroundEffect.shader = nil
            backgroundEffect.shouldEnableEffects = false
            return
        }
        shader.uniformNamed("u_texel")?.vectorFloat2Value = vector_float2(
            Float(1.0 / size.width), Float(1.0 / size.height)
        )
        backgroundEffect.shader = shader
        backgroundEffect.shouldEnableEffects = true
    }

    private func applyShader() {
        applyFill()
        applyBackgroundShader()
        applyField()
        guard let shader = SpriteShaders.shader(for: composition.globalShader) else {
            effectNode.shader = nil
            effectNode.shouldEnableEffects = false
            return
        }
        shader.uniformNamed("u_texel")?.vectorFloat2Value = vector_float2(
            Float(1.0 / size.width), Float(1.0 / size.height)
        )
        // Glass samples what is BEHIND the letters, which the text layer cannot see —
        // the background is a different node. Hand it in as a texture.
        if composition.globalShader.kind == .glass {
            shader.addUniform(SKUniform(
                name: "u_background",
                texture: BackgroundTextureFactory.texture(for: composition.background, size: size)
            ))
        }
        effectNode.shader = shader
        effectNode.shouldEnableEffects = true
        // A rebuilt shader starts with its uniforms at zero, so the current lean has to
        // be pushed back onto it. Live it would self-correct on the next reading; a
        // still export takes exactly one frame and would not.
        applyParallax()
    }

    private func applyField() {
        guard let field = SpriteShaders.field(for: composition.globalShader) else {
            fieldEffect.isHidden = true
            fieldEffect.shouldEnableEffects = false
            fieldEffect.filter = nil
            fieldEffect.shader = nil
            return
        }
        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.setValue(field.blurRadius, forKey: "inputRadius")
        fieldEffect.filter = blur
        fieldEffect.shader = field.shader
        fieldEffect.blendMode = field.additive ? .add : .alpha
        fieldEffect.shouldEnableEffects = true
        fieldEffect.isHidden = false
    }

    /// The field copies follow the live glyph nodes, so a halo moves with the letter
    /// it belongs to.
    private func syncFieldNodes() {
        guard !fieldEffect.isHidden else { return }
        for (id, mirror) in fieldNodes {
            guard let node = glyphNodes[id] else { continue }
            mirror.position = node.position
            mirror.zRotation = node.zRotation
            mirror.xScale = node.xScale
            mirror.yScale = node.yScale
        }
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
        var driftX: CGFloat = 0
        var driftY: CGFloat = 0
    }

    private var motion: [UUID: Motion] = [:]
    /// Node state captured the moment a touch begins, so releasing undoes only what
    /// the effect did — a shuffle applied beforehand survives.
    private var preInteractionState: [UUID: (position: CGPoint, rotation: CGFloat, scale: CGFloat)] = [:]
    private var caretNode: SKSpriteNode?
    private var caretIndex: Int?
    private var touchDownPoint: CGPoint?
    private var interactionStart: TimeInterval?
    private var lastAdvance: TimeInterval?

    /// Deterministic per-frame step. Called by the live scene's update and by the
    /// offscreen frame renderer, so both produce the same animation.
    func advance(to time: TimeInterval) {
        recordMotionIfNeeded(at: time)
        if interactionStart == nil { interactionStart = time }
        let elapsed = time - (interactionStart ?? time)
        let delta = min(1.0 / 20.0, max(0, time - (lastAdvance ?? time)))
        lastAdvance = time

        switch interaction {
        case .none:
            break

        case .warp:
            guard isHolding, let touch = touchPoint, abs(interactionAmount) > 0.01 else { break }
            let reach = size.width * 0.38
            // One bipolar control: positive bloats, negative puckers, 0 does nothing.
            let extent = interactionAmount >= 0
                ? 1 + interactionAmount * 2.0
                : 1 + interactionAmount * 0.75
            for node in glyphNodes.values {
                let centre = CGPoint(x: node.position.x + node.size.width / 2, y: node.position.y)
                let distance = hypot(centre.x - touch.x, centre.y - touch.y)
                let influence = max(0, 1 - distance / reach)
                let target = 1 + (extent - 1) * influence
                let rate = min(1, delta * 9)
                node.setScale(node.xScale + (target - node.xScale) * rate)
            }

        case .attract:
            guard isHolding, delta > 0, abs(interactionAmount) > 0.01 else { break }
            let pull = CGFloat(interactionAmount) * size.width * 5.5
            let damping: CGFloat = 0.90
            let target = touchPoint ?? CGPoint(x: size.width / 2, y: size.height / 2)

            for (id, node) in glyphNodes {
                var state = motion[id] ?? Motion()
                let seed = seedValue(for: id)

                let centre = CGPoint(x: node.position.x + node.size.width / 2, y: node.position.y)
                var dx = target.x - centre.x
                var dy = target.y - centre.y
                let distance = max(24, hypot(dx, dy))
                dx /= distance
                dy /= distance

                let wander = CGFloat(abs(interactionAmount))
                let wanderX = CGFloat(sin(elapsed * 1.3 + Double(seed) * 6.28)) * size.width * 0.10 * wander
                let wanderY = CGFloat(cos(elapsed * 1.1 + Double(seed) * 6.28)) * size.height * 0.10 * wander

                state.driftX += (dx * pull + wanderX) * delta
                state.driftY += (dy * pull + wanderY) * delta
                state.driftX *= damping
                state.driftY *= damping

                node.position.x += state.driftX * delta
                node.position.y += state.driftY * delta
                node.zRotation += CGFloat(sin(elapsed * 0.9 + Double(seed) * 6.28)) * 0.02

                // Soft boundary: at full push the letters otherwise shoot far past the
                // canvas and simply disappear. Let them leave, but not escape.
                let margin = size.width * 0.22
                if node.position.x < -margin || node.position.x > size.width + margin {
                    node.position.x = min(max(node.position.x, -margin), size.width + margin)
                    state.driftX *= -0.25
                }
                if node.position.y < -margin || node.position.y > size.height + margin {
                    node.position.y = min(max(node.position.y, -margin), size.height + margin)
                    state.driftY *= -0.25
                }
                motion[id] = state
            }

        case .gravity:
            guard delta > 0, abs(interactionAmount) > 0.01 else { break }
            // Positive falls, negative floats up, 0 leaves the letters alone.
            let accel = -size.height * CGFloat(interactionAmount) * 3.2
            let bounce: CGFloat = 0.32
            for (id, node) in glyphNodes {
                var state = motion[id] ?? Motion(velocity: 0, spin: (seedValue(for: id) - 0.5) * 3.2)
                state.velocity += accel * delta
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
                } else if node.position.y >= size.height - node.size.height / 2 {
                    // Symmetric with the floor: letters settle against the ceiling
                    // rather than wrapping around, which read as a glitch.
                    node.position.y = size.height - node.size.height / 2
                    state.velocity = -state.velocity * bounce
                    state.spin *= 0.45
                    if abs(state.velocity) < size.height * 0.06 {
                        state.velocity = 0
                        state.spin = 0
                    }
                }
                motion[id] = state
            }

        case .tilt:
            guard delta > 0, abs(interactionAmount) > 0.01 else { break }
            // Downhill is wherever the phone says it is, so this is the gravity
            // integrator with a DIRECTION rather than a fixed straight down.
            let pull = size.height * CGFloat(interactionAmount) * 2.6
            let accelX = tilt.dx * pull
            let accelY = tilt.dy * pull
            let friction: CGFloat = 0.94
            let bounce: CGFloat = 0.26

            if !didReportTilt, hypot(tilt.dx, tilt.dy) > 0.05 {
                didReportTilt = true
                onInteractionBegan?()
            }

            for (id, node) in glyphNodes {
                var state = motion[id] ?? Motion()
                state.driftX += accelX * delta
                state.driftY += accelY * delta
                state.driftX *= friction
                state.driftY *= friction

                node.position.x += state.driftX * delta
                node.position.y += state.driftY * delta
                // A letter sliding across the canvas tumbles a little.
                node.zRotation += state.driftX * delta * 0.0016

                // All four walls: letters slide sideways here, not only down.
                let halfWidth = node.size.width * node.xScale / 2
                let halfHeight = node.size.height * node.yScale / 2
                let centreX = node.position.x + halfWidth
                if centreX < halfWidth {
                    node.position.x += halfWidth - centreX
                    state.driftX = -state.driftX * bounce
                } else if centreX > size.width - halfWidth {
                    node.position.x -= centreX - (size.width - halfWidth)
                    state.driftX = -state.driftX * bounce
                }
                if node.position.y < halfHeight {
                    node.position.y = halfHeight
                    state.driftY = -state.driftY * bounce
                } else if node.position.y > size.height - halfHeight {
                    node.position.y = size.height - halfHeight
                    state.driftY = -state.driftY * bounce
                }

                // Come to rest instead of shivering in the corner.
                if abs(state.driftX) < size.width * 0.004 { state.driftX = 0 }
                if abs(state.driftY) < size.height * 0.004 { state.driftY = 0 }
                motion[id] = state
            }
        }

        resolveCollisions()
        syncFieldNodes()
    }

    /// The background slides against the tilt, which reads as depth between the type
    /// and whatever is behind it. The node is oversized so the shift never uncovers an
    /// edge.
    private func applyParallax() {
        let offset = CGPoint(
            x: -tilt.dx * size.width * parallaxReach,
            y: -tilt.dy * size.height * parallaxReach
        )
        backgroundNode.position = CGPoint(
            x: size.width / 2 + offset.x,
            y: size.height / 2 + offset.y
        )
        // Glass samples the background as a texture, so it has to be told the same
        // shift or the letters would refract a background that is no longer there.
        effectNode.shader?.uniformNamed("u_bg_shift")?.vectorFloat2Value = vector_float2(
            Float(offset.x / size.width), Float(offset.y / size.height)
        )
        // Light direction tracks the tilt, the way a real specular does.
        for shader in [effectNode.shader, backgroundEffect.shader, fieldEffect.shader] {
            shader?.uniformNamed("u_tilt")?.vectorFloat2Value = vector_float2(
                Float(tilt.dx), Float(tilt.dy)
            )
        }
    }

    // MARK: - Collision
    //
    // Circle proxies, resolved by splitting each overlap between the pair and bleeding
    // off the velocity that drove them together. A few relaxation passes settle a
    // stack; solving each pair once leaves letters jittering against each other.
    //
    // No SKPhysicsBody: SKRenderer barely steps the scene, so anything simulated by
    // SpriteKit itself would stand still in an export while moving on screen.

    private func collisionCentre(_ node: SKSpriteNode) -> CGPoint {
        CGPoint(x: node.position.x + node.size.width * node.xScale / 2, y: node.position.y)
    }

    /// A glyph's shape circles placed in the scene, following the node's rotation and
    /// scale.
    private func worldCircles(_ id: UUID) -> [(centre: CGPoint, radius: CGFloat)] {
        guard let node = glyphNodes[id], let shape = glyphShapes[id] else { return [] }
        let scale = node.xScale
        let angle = node.zRotation
        let cosine = cos(angle)
        let sine = sin(angle)
        return shape.map { circle in
            let x = circle.centre.x * scale
            let y = circle.centre.y * scale
            return (
                centre: CGPoint(
                    x: node.position.x + x * cosine - y * sine,
                    y: node.position.y + x * sine + y * cosine
                ),
                radius: circle.radius * scale
            )
        }
    }

    private func broadRadius(_ id: UUID) -> CGFloat {
        guard let node = glyphNodes[id] else { return 0 }
        return (glyphBounds[id] ?? min(node.size.width, node.size.height) / 2) * node.xScale
    }

    /// Overlaps shallower than this fraction of the pair's reach are left alone.
    /// Letters at rest graze each other, and resolving those pushed a word apart the
    /// moment collision was switched on.
    private static let collisionSlack: CGFloat = 0.08

    /// The combined contact between two glyphs' shapes.
    ///
    /// Every overlapping circle pair contributes, not just the deepest one. Resolving
    /// only the deepest pair can push two interlocked letters along a normal that
    /// immediately recreates an equally deep overlap somewhere else, and the pair sits
    /// there oscillating — measured at 32pt of permanent interpenetration in a pile.
    private func contact(
        _ a: [(centre: CGPoint, radius: CGFloat)],
        _ b: [(centre: CGPoint, radius: CGFloat)],
        fallback: CGVector
    ) -> (normal: CGVector, depth: CGFloat)? {
        var pushX: CGFloat = 0
        var pushY: CGFloat = 0
        var deepest: CGFloat = 0
        var widest: CGFloat = 0
        var hits = 0

        for first in a {
            for second in b {
                let dx = second.centre.x - first.centre.x
                let dy = second.centre.y - first.centre.y
                let reach = first.radius + second.radius
                var distance = hypot(dx, dy)
                guard distance < reach * (1 - Self.collisionSlack) else { continue }
                let depth = reach - distance
                // Coincident centres have no normal to push along. Pick a fixed one
                // rather than a random one, so the result is repeatable.
                if distance < 0.001 { distance = 0.001 }
                pushX += (dx / distance) * depth
                pushY += (dy / distance) * depth
                deepest = max(deepest, depth)
                widest = max(widest, max(first.radius, second.radius))
                hits += 1
            }
        }

        guard hits > 0 else { return nil }

        // Two cases need the line between the glyphs rather than a surface normal:
        //
        //  · nearly concentric shapes, whose contacts point every way at once and sum
        //    to nothing;
        //  · DEEP interpenetration, where resolving one contact simply creates an equal
        //    one on another face and the pair rocks between them forever. Measured as a
        //    pair sitting permanently 33pt inside each other while the resolver
        //    reported a push every single pass.
        let length = hypot(pushX, pushY)
        if length < deepest * 0.05 || deepest > widest * 0.9 {
            let span = hypot(fallback.dx, fallback.dy)
            guard span > 0.0001 else { return (CGVector(dx: 1, dy: 0), deepest) }
            return (CGVector(dx: fallback.dx / span, dy: fallback.dy / span), deepest)
        }
        return (CGVector(dx: pushX / length, dy: pushY / length), deepest)
    }

    private func resolveCollisions() {
        guard collisionsEnabled, orderedIds.count > 1 else { return }

        // Six passes, not three: under a constant push — gravity, or a tilt holding
        // letters against a corner — three left pairs still overlapping, because the
        // wall clamp shoves them back into each other between passes.
        for _ in 0..<6 {
            // Placed once per pass and reused across every pair in it.
            let placed = orderedIds.map { worldCircles($0) }
            let centres = orderedIds.map { glyphNodes[$0].map(collisionCentre) ?? .zero }
            let radii = orderedIds.map { broadRadius($0) }

            for i in 0..<(orderedIds.count - 1) {
                guard let a = glyphNodes[orderedIds[i]] else { continue }
                for j in (i + 1)..<orderedIds.count {
                    guard let b = glyphNodes[orderedIds[j]] else { continue }

                    // Broad phase: most pairs are nowhere near each other, and the
                    // shape test is 30-odd circle comparisons.
                    let span = hypot(centres[j].x - centres[i].x, centres[j].y - centres[i].y)
                    guard span < radii[i] + radii[j] else { continue }

                    guard let hit = contact(
                        placed[i], placed[j],
                        fallback: CGVector(dx: centres[j].x - centres[i].x,
                                           dy: centres[j].y - centres[i].y)
                    ) else { continue }
                    let push = hit.depth * 0.5

                    a.position.x -= hit.normal.dx * push
                    a.position.y -= hit.normal.dy * push
                    b.position.x += hit.normal.dx * push
                    b.position.y += hit.normal.dy * push

                    damp(orderedIds[i])
                    damp(orderedIds[j])
                }
            }
        }

        // Solid bodies stay on the table. Without this, collision could shove a letter
        // through the floor the gravity pass had just settled it on.
        for id in orderedIds {
            guard let node = glyphNodes[id] else { continue }
            // The glyph's own half-extents, NOT its bounding radius. The bounding
            // radius is half a diagonal, which held letters much further from the edge
            // than the interaction modes do — the two clamps then fought each frame and
            // left a corner pile permanently overlapping.
            let halfWidth = node.size.width * node.xScale / 2
            let halfHeight = node.size.height * node.yScale / 2
            let centre = collisionCentre(node)
            let clampedX = min(max(centre.x, halfWidth), size.width - halfWidth)
            let clampedY = min(max(centre.y, halfHeight), size.height - halfHeight)
            if clampedX != centre.x {
                node.position.x += clampedX - centre.x
                motion[id]?.driftX = 0
            }
            if clampedY != centre.y {
                node.position.y += clampedY - centre.y
                motion[id]?.velocity = 0
                motion[id]?.driftY = 0
            }
        }
    }

    /// Bleeds off the motion that drove a contact, so a pile settles rather than
    /// buzzing.
    private func damp(_ id: UUID) {
        guard var state = motion[id] else { return }
        state.velocity *= 0.45
        state.driftX *= 0.6
        state.driftY *= 0.6
        state.spin *= 0.6
        motion[id] = state
    }

    /// A stable pseudo-random value per glyph, from the UUID's own bytes.
    ///
    /// NOT `hashValue`: Swift seeds hashing per PROCESS, so the same saved composition
    /// would tumble differently every launch — and a recording made in one session
    /// could not be reproduced in the next.
    private func seedValue(for id: UUID) -> CGFloat {
        let bytes = id.uuid
        let mixed = UInt32(bytes.0) &* 73856093
            ^ UInt32(bytes.5) &* 19349663
            ^ UInt32(bytes.10) &* 83492791
            ^ UInt32(bytes.15) &* 2971215073
        return CGFloat(mixed % 1000) / 1000
    }

    private func resetMotion() {
        didReportTilt = false
        motion.removeAll()
        interactionStart = nil
        lastAdvance = nil
    }

    // MARK: - Test hooks
    //
    // DEBUG only: the release binary carries none of this. `SelfCheck` is the app's
    // test surface — there is no unit-test target because the parts worth testing only
    // behave correctly inside a real Metal context.

    #if DEBUG
    var debugGlyphNodeCount: Int { glyphNodes.count }

    /// Node positions in laid-out order, for comparing two runs of the same input.
    var debugOrderedPositions: [CGPoint] {
        orderedIds.compactMap { glyphNodes[$0]?.position }
    }

    var debugMeanGlyphScale: CGFloat {
        guard !glyphNodes.isEmpty else { return 1 }
        return glyphNodes.values.reduce(0) { $0 + $1.xScale } / CGFloat(glyphNodes.count)
    }

    var debugMeanAbsRotation: CGFloat {
        guard !glyphNodes.isEmpty else { return 0 }
        return glyphNodes.values.reduce(0) { $0 + abs($1.zRotation) } / CGFloat(glyphNodes.count)
    }

    /// Pairs whose collision proxies currently overlap. 0 means nothing is stacked.
    var debugOverlappingPairs: Int {
        var count = 0
        let placed = orderedIds.map { worldCircles($0) }
        for i in 0..<max(0, orderedIds.count - 1) {
            for j in (i + 1)..<orderedIds.count
            where contact(placed[i], placed[j], fallback: .zero)?.depth ?? 0 > 0.5 {
                count += 1
            }
        }
        return count
    }

    /// How deeply the worst-overlapping pair is interpenetrating, in points.
    var debugDeepestOverlap: CGFloat {
        let placed = orderedIds.map { worldCircles($0) }
        var worst: CGFloat = 0
        for i in 0..<max(0, orderedIds.count - 1) {
            for j in (i + 1)..<orderedIds.count {
                worst = max(worst, contact(placed[i], placed[j], fallback: .zero)?.depth ?? 0)
            }
        }
        return worst
    }

    func simulateTouchDown(at point: CGPoint) {
        touchPoint = point
        touchDownPoint = point
        isHolding = true
        resetMotion()
        capturePreInteractionState()
    }

    func simulateTouchUp() {
        isHolding = false
        touchPoint = nil
        touchDownPoint = nil
        if !isLocked, interaction != .gravity, interaction != .tilt { springBack() }
    }
    #endif

    // MARK: - Touch recording (v6 video)
    //
    // Video records what you DO, not just what the shader does on its own. Rather than
    // grabbing frames off the live view — which is pinned to the screen's scale and
    // drops frames — the touches are recorded here and replayed offscreen at full
    // resolution. Motion is deterministic given touch state, so the replay reproduces
    // exactly what was on screen.

    struct TouchSample: Hashable {
        var time: TimeInterval
        var point: CGPoint?
        var holding: Bool
        /// Tilt travels in the SAME track as the touches. A recording has to reproduce
        /// what the phone was doing as well as what the finger was doing, and one track
        /// cannot drift out of step with itself.
        var tilt: CGVector = .zero
    }

    private(set) var touchTrack: [TouchSample] = []
    private var touchRecordingStart: TimeInterval?

    func beginTouchRecording() {
        touchTrack = [TouchSample(time: 0, point: nil, holding: false)]
        touchRecordingStart = lastAdvance ?? 0
    }

    func endTouchRecording() -> [TouchSample] {
        touchRecordingStart = nil
        return touchTrack
    }

    private func recordTouch() {
        guard let start = touchRecordingStart, let last = lastAdvance else { return }
        touchTrack.append(
            TouchSample(time: last - start, point: touchPoint, holding: isHolding, tilt: tilt)
        )
    }

    /// Tilt arrives without a touch, so a recording of it has to be sampled on the
    /// clock instead. Every frame, not throttled: a sampling gap is a place where the
    /// replay can diverge from what was on screen, and four seconds of samples is a few
    /// hundred structs.
    private func recordMotionIfNeeded(at time: TimeInterval) {
        guard interaction == .tilt, let start = touchRecordingStart else { return }
        touchTrack.append(
            TouchSample(time: time - start, point: touchPoint, holding: isHolding, tilt: tilt)
        )
    }

    /// Replay: drive the scene from a recorded track instead of live touches.
    func applyRecordedTouch(track: [TouchSample], at time: TimeInterval) {
        guard !track.isEmpty else { return }
        var chosen = track[0]
        for sample in track where sample.time <= time { chosen = sample }
        touchPoint = chosen.point
        isHolding = chosen.holding
        tilt = chosen.tilt
    }

    // MARK: - Caret
    //
    // v6 edits text in the canvas rather than in a field below it. The caret is a real
    // node in the scene, positioned from the same layout the glyphs use.

    func setCaret(index: Int?) {
        caretIndex = index
        rebuildCaret()
    }

    private func rebuildCaret() {
        caretNode?.removeFromParent()
        caretNode = nil

        guard let index = caretIndex, let placement = caretPosition(for: index) else { return }

        let bar = SKSpriteNode(
            color: .white,
            size: CGSize(width: max(4, composition.dominantSize * 0.045), height: placement.height * 0.86)
        )
        bar.position = placement.point
        bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        bar.zPosition = 100
        bar.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.12, duration: 0.5),
            .fadeAlpha(to: 0.95, duration: 0.5),
        ])))
        addChild(bar)
        caretNode = bar
    }

    /// Where the caret sits for a given insertion index.
    func caretPosition(for index: Int) -> (point: CGPoint, height: CGFloat)? {
        let glyphs = composition.glyphs
        let fallback = (
            point: CGPoint(x: size.width / 2, y: size.height / 2),
            height: composition.dominantSize
        )
        guard !glyphs.isEmpty else { return fallback }

        if index < glyphs.count,
           let node = glyphNodes[glyphs[index].id],
           let rest = restPositions[glyphs[index].id] {
            return (CGPoint(x: rest.x, y: rest.y), node.size.height)
        }

        // Caret past the end, or on a line-break glyph that has no node: walk back to
        // the last glyph that was actually laid out.
        var cursor = min(index, glyphs.count) - 1
        while cursor >= 0 {
            if let node = glyphNodes[glyphs[cursor].id],
               let rest = restPositions[glyphs[cursor].id] {
                return (CGPoint(x: rest.x + node.size.width, y: rest.y), node.size.height)
            }
            cursor -= 1
        }
        return fallback
    }

    /// Nearest insertion point to a tap. Vertical distance is weighted so a tap picks
    /// the right LINE first, then the nearest gap on it.
    func caretIndex(atScenePoint point: CGPoint) -> Int {
        let glyphs = composition.glyphs
        guard !glyphs.isEmpty else { return 0 }

        var best = 0
        var bestScore = CGFloat.greatestFiniteMagnitude

        for (index, glyph) in glyphs.enumerated() {
            guard let node = glyphNodes[glyph.id], let rest = restPositions[glyph.id] else { continue }
            let candidates: [(CGFloat, Int)] = [
                (rest.x, index),
                (rest.x + node.size.width, index + 1),
            ]
            for (boundaryX, candidateIndex) in candidates {
                let score = abs(point.y - rest.y) * 2.2 + abs(point.x - boundaryX)
                if score < bestScore {
                    bestScore = score
                    best = candidateIndex
                }
            }
        }
        return best
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        touchPoint = point
        touchDownPoint = point
        isHolding = true
        resetMotion()
        capturePreInteractionState()
        recordTouch()
        if interaction != .none { onInteractionBegan?() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchPoint = touches.first?.location(in: self)
        recordTouch()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let end = touches.first?.location(in: self) ?? touchDownPoint
        var travelled: CGFloat = 0
        if let down = touchDownPoint, let end {
            travelled = hypot(end.x - down.x, end.y - down.y)
        }

        isHolding = false
        touchPoint = nil
        touchDownPoint = nil
        recordTouch()

        if interaction == .none {
            // A tap with no mode active moves the insertion point.
            if travelled < 14, let end {
                onCaretTap?(caretIndex(atScenePoint: end))
            }
            return
        }
        // Locked keeps whatever the letters are doing; unlocked settles them back.
        if !isLocked, interaction != .gravity, interaction != .tilt { springBack() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func capturePreInteractionState() {
        preInteractionState = glyphNodes.mapValues {
            (position: $0.position, rotation: $0.zRotation, scale: $0.xScale)
        }
    }

    /// Returns every glyph to the state it was in when the touch started — NOT to the
    /// laid-out grid. A shuffle applied before the gesture stays shuffled.
    private func springBack() {
        for (id, node) in glyphNodes {
            guard let before = preInteractionState[id] else { continue }
            node.removeAllActions()
            node.run(.group([
                .move(to: before.position, duration: 0.4),
                .scale(to: before.scale, duration: 0.4),
                .rotate(toAngle: before.rotation, duration: 0.4, shortestUnitArc: true),
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
