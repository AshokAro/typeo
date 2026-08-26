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
    case none, warp, attract, gravity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:    "Off"
        case .warp:    "Warp"
        case .attract: "Attract"
        case .gravity: "Gravity"
        }
    }

    var systemImage: String {
        switch self {
        case .none:    "hand.raised.slash"
        case .warp:    "circle.circle"
        case .attract: "hurricane"
        case .gravity: "arrow.up.arrow.down"
        }
    }

    var amountLabel: String {
        switch self {
        case .none:    ""
        case .warp:    "Warp"      // negative puckers, positive bloats
        case .attract: "Pull"      // negative pushes away, positive pulls in
        case .gravity: "Gravity"   // negative floats up, positive falls down
        }
    }

    /// Bipolar controls sit at 0 and do nothing until moved either way.
    var amountRange: ClosedRange<Double> {
        switch self {
        case .none:    0...0
        case .warp:    -1...1
        case .attract: -1...1
        case .gravity: -1...1
        }
    }

    var defaultAmount: Double {
        switch self {
        case .none:    0
        case .warp:    0
        case .attract: 0
        case .gravity: 0
        }
    }

    /// Wording for the readout at either end of a bipolar slider.
    func amountDetail(_ value: Double) -> String {
        switch self {
        case .warp:
            if value > 0.02 { return "bloat \(Int(value * 100))%" }
            if value < -0.02 { return "pucker \(Int(-value * 100))%" }
            return "none"
        case .gravity:
            if value > 0.02 { return "fall \(Int(value * 100))%" }
            if value < -0.02 { return "float \(Int(-value * 100))%" }
            return "still"
        case .attract:
            if value > 0.02 { return "pull \(Int(value * 100))%" }
            if value < -0.02 { return "push \(Int(-value * 100))%" }
            return "still"
        case .none:
            return ""
        }
    }
}

final class GlyphScene: SKScene {

    private(set) var composition: Composition
    var interaction: GlyphInteraction = .none
    /// Meaning depends on the mode: bloat/pucker size, attract pull (0 = zero-g),
    /// drop gravity.
    var interactionAmount: Double = 0
    /// When locked, releasing a touch does NOT spring the letters back, so a state can
    /// be held still for a screenshot or an export.
    var isLocked = false

    /// Called when the canvas is tapped with no interaction mode active, so the editor
    /// can move the insertion point. Carries the caret index the tap landed on.
    var onCaretTap: ((Int) -> Void)?

    private var glyphNodes: [UUID: SKSpriteNode] = [:]
    private var restPositions: [UUID: CGPoint] = [:]
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
        restPositions.removeAll()

        size = composition.aspectRatio.referenceSize

        backgroundEffect = SKEffectNode()
        backgroundEffect.zPosition = -10
        backgroundEffect.shouldRasterize = false
        addChild(backgroundEffect)

        backgroundNode = BackgroundTextureFactory.node(for: composition.background, size: size)
        backgroundNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundEffect.addChild(backgroundNode)

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

            glyphNodes[glyph.id] = node
            fillNode.addChild(node)
        }

        applyShader()
        rebuildCaret()
    }

    private func applyAppearance() {
        // Background lives on its own node, so it has to be refreshed here too —
        // otherwise a colour change only appeared the next time something forced a
        // full rebuild.
        backgroundNode.removeFromParent()
        backgroundNode = BackgroundTextureFactory.node(for: composition.background, size: size)
        backgroundNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundEffect.addChild(backgroundNode)

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

    // MARK: - Test hooks

    var currentComposition: Composition { composition }

    var debugMeanGlyphY: CGFloat {
        guard !glyphNodes.isEmpty else { return 0 }
        return glyphNodes.values.reduce(0) { $0 + $1.position.y } / CGFloat(glyphNodes.count)
    }

    var debugMeanGlyphScale: CGFloat {
        guard !glyphNodes.isEmpty else { return 1 }
        return glyphNodes.values.reduce(0) { $0 + $1.xScale } / CGFloat(glyphNodes.count)
    }

    var debugMeanAbsRotation: CGFloat {
        guard !glyphNodes.isEmpty else { return 0 }
        return glyphNodes.values.reduce(0) { $0 + abs($1.zRotation) } / CGFloat(glyphNodes.count)
    }

    var debugPreInteractionMeanAbsRotation: CGFloat {
        guard !preInteractionState.isEmpty else { return 0 }
        return preInteractionState.values.reduce(0) { $0 + abs($1.rotation) } / CGFloat(preInteractionState.count)
    }

    func debugMeanDistance(to point: CGPoint) -> CGFloat {
        guard !glyphNodes.isEmpty else { return 0 }
        return glyphNodes.values.reduce(0) {
            $0 + hypot($1.position.x - point.x, $1.position.y - point.y)
        } / CGFloat(glyphNodes.count)
    }

    var debugHasSpringBackActions: Bool {
        glyphNodes.values.contains { $0.hasActions() }
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
        if !isLocked, interaction != .gravity { springBack() }
    }

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
            TouchSample(time: last - start, point: touchPoint, holding: isHolding)
        )
    }

    /// Replay: drive the scene from a recorded track instead of live touches.
    func applyRecordedTouch(track: [TouchSample], at time: TimeInterval) {
        guard !track.isEmpty else { return }
        var chosen = track[0]
        for sample in track where sample.time <= time { chosen = sample }
        touchPoint = chosen.point
        isHolding = chosen.holding
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
        if !isLocked, interaction != .gravity { springBack() }
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
