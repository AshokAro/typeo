//
//  SelfCheck.swift
//  Typeo
//
//  The app's test surface.
//
//  There is no unit-test target: the whole app is one UI, and the parts worth testing —
//  shaders, the SpriteKit canvas, the export path — only behave correctly inside a real
//  Metal context, which is why every bug worth catching here has been caught by
//  rendering something and looking at the numbers rather than by asserting on a value.
//
//  DEBUG only. Run with `-selfCheck` on the launch arguments; the report is printed and
//  written to Documents/selfcheck.txt.
//

#if DEBUG
import SwiftUI
import SpriteKit

@MainActor
enum SelfCheck {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-selfCheck")
    }

    private static var lines: [String] = []
    private static var failures = 0
    private static var checks = 0

    private static func expect(_ condition: Bool, _ label: String, _ detail: String = "") {
        checks += 1
        if !condition { failures += 1 }
        let mark = condition ? "PASS" : "FAIL"
        lines.append("  [\(mark)] \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    }

    private static func section(_ title: String) {
        lines.append("")
        lines.append(title)
    }

    static func run() {
        lines = []
        failures = 0
        checks = 0

        model()
        store()
        layout()
        caches()
        canvas()
        shaders()
        interactions()
        backgrounds()
        persistence()
        widget()
        exporting()

        let summary = failures == 0
            ? "ALL \(checks) CHECKS PASSED"
            : "\(failures) OF \(checks) CHECKS FAILED"
        let report = ([summary] + lines).joined(separator: "\n")
        print("SELFCHECK\n" + report)
        try? report.write(to: URL.documentsDirectory.appendingPathComponent("selfcheck.txt"),
                          atomically: true, encoding: .utf8)
    }

    // MARK: Fixtures

    private static func sample(_ text: String = "TYPEO") -> Composition {
        var composition = Composition()
        composition.glyphs = text.map {
            Glyph(character: String($0), font: .system, size: 170, color: .white)
        }
        return composition
    }

    // MARK: Checks

    private static func model() {
        section("model")

        // Every raw value is a promise to files already on disk.
        let expected = ["none", "bloom", "heat", "noise", "glitch", "chrome", "glass",
                        "matrix", "liquify", "halftone", "motionBlur", "thermal", "neon",
                        "gemSmoke", "meshGradient", "grainGradient", "dithering",
                        "flutedGlass", "lensDistort"]
        expect(ShaderEffect.Kind.allCases.map(\.rawValue) == expected,
               "shader kind raw values unchanged",
               ShaderEffect.Kind.allCases.map(\.rawValue).joined(separator: ","))
        expect(!ShaderEffect.Kind.selectable.contains(.gemSmoke),
               "retired kind hidden but still decodable")

        var composition = sample()
        composition.globalShader = ShaderEffect(kind: .lensDistort, intensity: -0.4,
                                                secondary: 0.2, tertiary: 0.7, variant: 2)
        composition.backgroundShader = ShaderEffect(kind: .flutedGlass, intensity: 0.6)
        composition.textGradient = .sunset
        composition.background = .image(id: "builtin:dusk")
        composition.alignment = .trailing
        composition.letterSpacing = 12
        composition.lineHeightMultiple = 1.4
        do {
            let data = try JSONEncoder().encode(composition)
            let back = try JSONDecoder().decode(Composition.self, from: data)
            expect(back == composition, "composition round trip")
        } catch {
            expect(false, "composition round trip", "\(error)")
        }

        // A file written before any of the v6 fields existed.
        let legacy = """
        {"id":"6C7C1E9E-2D0B-4E6E-9B2E-000000000001","createdAt":700000000,
         "aspectRatio":"1:1",
         "background":{"solid":{"_0":{"red":0,"green":0,"blue":0,"opacity":1}}},
         "globalShader":{"kind":"bloom","intensity":0.5},
         "glyphs":[{"id":"6C7C1E9E-2D0B-4E6E-9B2E-000000000002","character":"A",
           "font":{"design":"standard"},"size":150,
           "color":{"red":1,"green":1,"blue":1,"opacity":1},
           "positionOffset":[0,0],"rotation":0,"role":"glyph"}]}
        """
        do {
            let old = try JSONDecoder().decode(Composition.self, from: Data(legacy.utf8))
            expect(old.glyphs.count == 1 && old.resolvedAlignment == .center
                   && old.globalShader.tertiary == nil,
                   "pre-v6 file still decodes")
        } catch {
            expect(false, "pre-v6 file still decodes", "\(error)")
        }

        expect(AspectRatio.allCases.allSatisfy { $0.referenceSize.width >= 1080 },
               "every aspect renders at 1080 or wider")
    }

    private static func store() {
        section("store")
        let store = CompositionStore()

        var caret = store.insertText("HI", at: 0)
        expect(store.text == "HI" && caret == 2, "insert at caret")
        caret = store.insertText("!", at: caret)
        expect(store.text == "HI!" , "insert at end")
        let ids = store.composition.glyphs.map(\.id)
        _ = store.insertText("X", at: 1)
        expect(Array(store.composition.glyphs.map(\.id).filter { ids.contains($0) }) == ids,
               "glyph identity survives an insert")
        caret = store.deleteBackward(at: 2)
        expect(store.text == "HI!" && caret == 1, "delete backward")

        // Checkpoints coalesce a burst of typing into ONE step on purpose, so undo
        // walks back over the burst rather than a keystroke.
        let typed = store.text
        store.undo()
        expect(store.text != typed, "undo steps back", "\"\(typed)\" -> \"\(store.text)\"")
        store.redo()
        expect(store.text == typed, "redo returns")

        store.setColor(RGBAColor(red: 1, green: 0, blue: 0))
        expect(store.composition.glyphs.allSatisfy { $0.color.red == 1 && $0.color.green == 0 },
               "colour writes to every glyph")

        store.beginLiveJumble()
        store.updateLiveJumble(amount: 0)
        let scattered = store.composition.glyphs
        expect(scattered.allSatisfy { $0.positionOffset == .zero },
               "shuffle never moves letters")
        expect(scattered.contains { $0.rotation != 0 }, "shuffle tilts at amount 0")
        store.updateLiveJumble(amount: 1)
        expect(Set(store.composition.glyphs.map(\.font)).count > 1
               || store.composition.glyphs.count < 2,
               "shuffle restyles at amount 1")
        store.endLiveJumble()
        store.unjumble()
        expect(store.composition.glyphs.allSatisfy { $0.rotation == 0 }, "unjumble clears")

        for preset in StylePreset.all {
            store.apply(preset)
            expect(store.composition.globalShader.kind == preset.shader.kind,
                   "preset \(preset.name) applies")
        }

        store.updateEffect(background: true) { $0.kind = .meshGradient }
        expect(store.composition.backgroundShader?.kind == .meshGradient, "background effect set")
        store.updateEffect(background: true) { $0.kind = .none }
        expect(store.composition.backgroundShader == nil, "background effect cleared to nil")
    }

    /// Caches that grow with every step of a slider are how a canvas app runs a device
    /// out of memory.
    private static func caches() {
        section("caches")
        let store = CompositionStore()
        store.insertText("TYPEO", at: 0)
        for size in stride(from: 40.0, through: 420.0, by: 2.0) {
            store.setSize(CGFloat(size))
            _ = store.composition.glyphs.map { GlyphTextureFactory.texture(for: $0) }
        }
        expect(GlyphTextureFactory.debugCacheCount <= 240 + 5,
               "glyph texture cache stays bounded",
               "\(GlyphTextureFactory.debugCacheCount) entries after 190 sizes")
    }

    private static func layout() {
        section("layout")
        let composition = sample("TYPEO WORLD")
        let metrics = composition.glyphs.map { GlyphTextureFactory.metric(for: $0) }
        let laid = GlyphLayoutEngine.layout(
            metrics: metrics, maxWidth: 950,
            lineSpacing: 24, fallbackLineHeight: 150,
            letterSpacing: 0, alignment: .center
        )
        expect(laid.placements.count == metrics.filter { $0.role == .glyph }.count,
               "every glyph is placed")
        expect(laid.size.width <= 950 + 1, "wrapping respects the measured width",
               "width \(Int(laid.size.width))")

        let shapes = GlyphShapeFactory.circles(
            for: Glyph(character: "T", font: .system, size: 150, color: .white))
        expect(shapes.count > 1, "collision proxy follows the letterform",
               "\(shapes.count) circles")
    }

    private static func canvas() {
        section("canvas")
        let composition = sample()
        let scene = GlyphScene(composition: composition, size: composition.aspectRatio.referenceSize)
        scene.rebuild()
        expect(scene.debugGlyphNodeCount == 5, "a node per glyph")

        // Caret placement drives in-canvas editing.
        let index = scene.caretIndex(atScenePoint: CGPoint(x: 0, y: 540))
        expect(index >= 0 && index <= composition.glyphs.count, "caret index is in range")
        expect(scene.caretPosition(for: 0) != nil, "caret has a position")

        // Model transforms must reach the nodes, or a shuffle cannot be seen.
        var tilted = composition
        tilted.glyphs.indices.forEach { tilted.glyphs[$0].rotation = 12 }
        scene.update(composition: tilted)
        expect(abs(scene.debugMeanAbsRotation) > 0.05, "rotation reaches the nodes")
    }

    private static func shaders() {
        section("shaders")
        guard let base = CompositionRenderer.render(sample(), time: 0, scale: 0.5) else {
            expect(false, "baseline renders")
            return
        }

        for kind in ShaderEffect.Kind.allCases where kind != .none {
            var composition = sample()
            composition.globalShader = ShaderEffect(kind: kind, intensity: 0.85,
                                                    secondary: 0.5, tertiary: 0.5)
            guard let image = CompositionRenderer.render(composition, time: 0, scale: 0.5),
                  let difference = Ink.difference(base, image) else {
                expect(false, "\(kind.rawValue) renders")
                continue
            }
            // A shader that fails to compile is applied silently as NOTHING, so the only
            // proof it ran is that pixels moved. Compared per pixel: a whole-frame mean
            // is dominated by the background, which the text shaders never touch.
            expect(difference.changed > 500, "\(kind.rawValue) changes the render",
                   "\(difference.changed) px, max delta \(difference.maxDelta)")
        }

        // Background shaders are a separate layer over a separate node.
        var background = sample()
        background.background = .image(id: "builtin:bloom")
        background.backgroundShader = ShaderEffect(kind: .flutedGlass, intensity: 0.8)
        var plain = background
        plain.backgroundShader = nil
        if let shaded = CompositionRenderer.render(background, time: 0, scale: 0.5),
           let unshaded = CompositionRenderer.render(plain, time: 0, scale: 0.5),
           let difference = Ink.difference(unshaded, shaded) {
            expect(difference.changed > 20_000, "background effect repaints the background",
                   "\(difference.changed) px")
        } else {
            expect(false, "background effect renders")
        }
    }

    private static func interactions() {
        section("interactions")
        for mode in GlyphInteraction.allCases where mode != .none {
            let composition = sample()
            let scene = GlyphScene(composition: composition, size: composition.aspectRatio.referenceSize)
            scene.rebuild()
            scene.interaction = mode
            scene.interactionAmount = 1
            scene.tilt = CGVector(dx: 0.6, dy: -0.6)
            scene.simulateTouchDown(at: CGPoint(x: 300, y: 300))
            let before = scene.debugOrderedPositions
            let scaleBefore = scene.debugMeanGlyphScale
            for frame in 0..<120 { scene.advance(to: Double(frame) / 60.0) }
            let moved = zip(before, scene.debugOrderedPositions)
                .map { hypot($1.x - $0.x, $1.y - $0.y) }.max() ?? 0
            // Warp is the one mode that resizes rather than relocates.
            let changed = mode == .warp
                ? abs(scene.debugMeanGlyphScale - scaleBefore) > 0.01
                : moved > 1
            expect(changed, "\(mode.rawValue) changes the letters",
                   mode == .warp
                       ? String(format: "scale %.2f", scene.debugMeanGlyphScale)
                       : String(format: "%.0fpt", moved))
            expect(scene.debugOrderedPositions.allSatisfy { $0.x.isFinite && $0.y.isFinite },
                   "\(mode.rawValue) stays finite")
        }

        // Collision: piled letters separate, resting letters do not move.
        var piled = sample()
        piled.letterSpacing = -110
        let scene = GlyphScene(composition: piled, size: piled.aspectRatio.referenceSize)
        scene.rebuild()
        scene.collisionsEnabled = true
        let overlapsBefore = scene.debugOverlappingPairs
        for frame in 0..<120 { scene.advance(to: Double(frame) / 60.0) }
        expect(overlapsBefore > 0 && scene.debugDeepestOverlap < 8,
               "collision separates a pile",
               "\(overlapsBefore) pairs -> \(scene.debugOverlappingPairs), deepest "
               + String(format: "%.1fpt", scene.debugDeepestOverlap))

        let resting = GlyphScene(composition: sample(), size: AspectRatio.square.referenceSize)
        resting.rebuild()
        let restBefore = resting.debugOrderedPositions
        resting.collisionsEnabled = true
        for frame in 0..<60 { resting.advance(to: Double(frame) / 60.0) }
        let drift = zip(restBefore, resting.debugOrderedPositions)
            .map { hypot($1.x - $0.x, $1.y - $0.y) }.max() ?? 0
        expect(drift < 0.5, "collision leaves resting text alone", String(format: "%.2fpt", drift))

        // Determinism is what makes a recording match the screen.
        let fixed = sample()
        func run() -> [CGPoint] {
            let scene = GlyphScene(composition: fixed, size: AspectRatio.square.referenceSize)
            scene.rebuild()
            scene.interaction = .gravity
            scene.interactionAmount = 1
            scene.collisionsEnabled = true
            for frame in 0..<120 { scene.advance(to: Double(frame) / 60.0) }
            return scene.debugOrderedPositions
        }
        expect(run() == run(), "the same input lands in the same place")
    }

    private static func backgrounds() {
        section("backgrounds")
        for item in BuiltInBackgrounds.all {
            expect(BackgroundImageStore.image(for: item.id) != nil, "built-in \(item.name) draws")
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let picked = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 90), format: format)
            .image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
            }
        if let id = BackgroundImageStore.save(picked) {
            expect(BackgroundImageStore.image(for: id) != nil, "picked photo saves and reloads")
            expect(BackgroundImageStore.texture(for: id, size: CGSize(width: 1080, height: 1080)) != nil,
                   "picked photo fills the canvas")
            try? FileManager.default.removeItem(at: BackgroundImageStore.url(for: id))
        } else {
            expect(false, "picked photo saves")
        }
    }

    private static func persistence() {
        section("persistence")
        let directory = URL.documentsDirectory.appending(path: "SelfCheckLibrary")
        try? FileManager.default.removeItem(at: directory)
        let library = CompositionLibrary(directory: directory)
        var composition = sample("SAVED")
        composition.globalShader = ShaderEffect(kind: .neon, intensity: 0.7, secondary: 0.2)

        expect(library.save(composition), "library saves")
        let reopened = CompositionLibrary(directory: directory)
        expect(reopened.compositions.first == composition, "library reloads byte-identically")
        reopened.delete(composition)
        expect(CompositionLibrary(directory: directory).compositions.isEmpty, "library deletes")
        try? FileManager.default.removeItem(at: directory)
    }

    private static func widget() {
        section("widget")
        let pins = WidgetPinStore()
        let before = pins.entries.count
        let composition = sample("PINNED")
        expect(pins.pin(composition), "pinning renders and records")
        expect(pins.isPinned(composition.id), "pin is visible in the manifest")
        expect(pins.entries.first(where: { $0.id == composition.id })
            .map { pins.image(for: $0) != nil } ?? false, "pinned image is readable")

        let plan = WidgetTimelinePlan.plan(for: pins.manifest, startingAt: Date(timeIntervalSince1970: 0))
        expect(plan.slots.count == pins.entries.count, "timeline has a slot per entry")
        expect(plan.reloadAfter > Date(timeIntervalSince1970: 0), "timeline asks to be refreshed")

        pins.unpin(composition.id)
        expect(pins.entries.count == before, "unpinning cleans up")
    }

    private static func exporting() {
        section("export")
        for ratio in AspectRatio.allCases {
            var composition = sample()
            composition.aspectRatio = ratio
            guard let image = CompositionRenderer.render(composition, time: 0, scale: 1) else {
                expect(false, "\(ratio.label) still export")
                continue
            }
            expect(image.size == ratio.referenceSize, "\(ratio.label) exports at reference size",
                   "\(Int(image.size.width))x\(Int(image.size.height))")
        }

        guard let scaled = CompositionRenderer.render(sample(), time: 0, scale: 2) else { return }
        expect(scaled.size.width == 2160, "2x export doubles the pixels")
    }

    /// Ink statistics over a render. Mean colour and coverage are what catch a shader
    /// that compiled, ran, and did nothing.
    struct Ink {
        var coverage: Int
        var red: Double
        var green: Double
        var blue: Double

        /// Per-pixel comparison of two renders of the same size.
        static func difference(_ a: UIImage, _ b: UIImage) -> (changed: Int, maxDelta: Int)? {
            guard let left = bytes(a), let right = bytes(b), left.count == right.count else { return nil }
            var changed = 0
            var maxDelta = 0
            for index in stride(from: 0, to: left.count, by: 4) {
                var worst = 0
                for channel in 0..<3 {
                    worst = max(worst, abs(Int(left[index + channel]) - Int(right[index + channel])))
                }
                if worst > 3 { changed += 1 }
                maxDelta = max(maxDelta, worst)
            }
            return (changed, maxDelta)
        }

        private static func bytes(_ image: UIImage) -> [UInt8]? {
            guard let cgImage = image.cgImage else { return nil }
            let width = cgImage.width, height = cgImage.height
            var raw = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &raw, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return raw
        }

        static func measure(_ image: UIImage) -> Ink? {
            guard let cgImage = image.cgImage else { return nil }
            let width = cgImage.width, height = cgImage.height
            var raw = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &raw, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            var coverage = 0
            var r = 0.0, g = 0.0, b = 0.0
            for index in stride(from: 0, to: raw.count, by: 4) {
                let red = Double(raw[index]), green = Double(raw[index + 1]), blue = Double(raw[index + 2])
                if 0.299 * red + 0.587 * green + 0.114 * blue > 18 {
                    coverage += 1
                    r += red; g += green; b += blue
                }
            }
            let n = Double(max(1, coverage))
            return Ink(coverage: coverage, red: r / n, green: g / n, blue: b / n)
        }
    }
}
#endif
