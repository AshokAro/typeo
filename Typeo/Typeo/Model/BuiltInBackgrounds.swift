//
//  BuiltInBackgrounds.swift
//  Typeo
//
//  Photo backgrounds you can use without opening the photo library. Drawn rather than
//  bundled: no asset weight, no licence to check, and they render at whatever size the
//  canvas asks for.
//
//  Ids are namespaced `builtin:` so BackgroundImageStore can tell them from a picked
//  photo — a composition saved with one of these keeps working on any device, because
//  there is no file to go missing.
//

import UIKit

enum BuiltInBackgrounds {

    struct Item: Identifiable, Hashable {
        var id: String
        var name: String
    }

    static let all: [Item] = [
        Item(id: "builtin:dusk", name: "Dusk"),
        Item(id: "builtin:studio", name: "Studio"),
        Item(id: "builtin:bloom", name: "Bloom"),
        Item(id: "builtin:paper", name: "Paper"),
        Item(id: "builtin:ember", name: "Ember"),
        Item(id: "builtin:deep", name: "Deep"),
    ]

    static let prefix = "builtin:"

    static func isBuiltIn(_ id: String) -> Bool { id.hasPrefix(prefix) }

    private static var cache: [String: UIImage] = [:]

    static func image(for id: String) -> UIImage? {
        if let cached = cache[id] { return cached }
        guard all.contains(where: { $0.id == id }) else { return nil }

        let side: CGFloat = 1440
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { context in
                draw(id: id, in: context.cgContext, side: side)
            }
        cache[id] = image
        return image
    }

    // MARK: Drawing

    private static func draw(id: String, in context: CGContext, side: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)

        switch id {
        case "builtin:dusk":
            linear(context, rect,
                   colours: [rgb(0.05, 0.06, 0.16), rgb(0.29, 0.16, 0.35), rgb(0.94, 0.48, 0.35)],
                   from: CGPoint(x: 0.5, y: 0), to: CGPoint(x: 0.5, y: 1), side: side)
            radial(context, centre: CGPoint(x: 0.5, y: 0.92), radius: 0.55,
                   colours: [rgb(1.0, 0.72, 0.42, 0.85), rgb(1.0, 0.72, 0.42, 0)], side: side)

        case "builtin:studio":
            fill(context, rect, rgb(0.07, 0.07, 0.08))
            radial(context, centre: CGPoint(x: 0.5, y: 0.38), radius: 0.72,
                   colours: [rgb(0.30, 0.31, 0.34, 1), rgb(0.07, 0.07, 0.08, 0)], side: side)

        case "builtin:bloom":
            fill(context, rect, rgb(0.03, 0.02, 0.07))
            radial(context, centre: CGPoint(x: 0.24, y: 0.28), radius: 0.55,
                   colours: [rgb(0.95, 0.20, 0.55, 0.95), rgb(0.95, 0.20, 0.55, 0)], side: side)
            radial(context, centre: CGPoint(x: 0.78, y: 0.34), radius: 0.52,
                   colours: [rgb(0.25, 0.40, 1.00, 0.95), rgb(0.25, 0.40, 1.00, 0)], side: side)
            radial(context, centre: CGPoint(x: 0.52, y: 0.82), radius: 0.58,
                   colours: [rgb(0.10, 0.85, 0.70, 0.90), rgb(0.10, 0.85, 0.70, 0)], side: side)

        case "builtin:paper":
            fill(context, rect, rgb(0.93, 0.91, 0.86))
            radial(context, centre: CGPoint(x: 0.5, y: 0.5), radius: 0.95,
                   colours: [rgb(0, 0, 0, 0), rgb(0.35, 0.30, 0.22, 0.30)], side: side)

        case "builtin:ember":
            linear(context, rect,
                   colours: [rgb(0.11, 0.03, 0.02), rgb(0.55, 0.10, 0.05), rgb(0.98, 0.62, 0.18)],
                   from: CGPoint(x: 0.1, y: 1), to: CGPoint(x: 0.9, y: 0), side: side)

        case "builtin:deep":
            linear(context, rect,
                   colours: [rgb(0.01, 0.05, 0.12), rgb(0.02, 0.18, 0.28), rgb(0.03, 0.36, 0.40)],
                   from: CGPoint(x: 0, y: 0), to: CGPoint(x: 1, y: 1), side: side)
            radial(context, centre: CGPoint(x: 0.72, y: 0.22), radius: 0.5,
                   colours: [rgb(0.40, 0.95, 0.95, 0.35), rgb(0.40, 0.95, 0.95, 0)], side: side)

        default:
            fill(context, rect, rgb(0.1, 0.1, 0.1))
        }

        grain(context, rect, alpha: id == "builtin:paper" ? 0.14 : 0.05)
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func fill(_ context: CGContext, _ rect: CGRect, _ colour: UIColor) {
        context.setFillColor(colour.cgColor)
        context.fill(rect)
    }

    private static func linear(_ context: CGContext, _ rect: CGRect, colours: [UIColor],
                               from: CGPoint, to: CGPoint, side: CGFloat) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colours.map(\.cgColor) as CFArray,
                                        locations: nil) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: from.x * side, y: from.y * side),
            end: CGPoint(x: to.x * side, y: to.y * side),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func radial(_ context: CGContext, centre: CGPoint, radius: CGFloat,
                               colours: [UIColor], side: CGFloat) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colours.map(\.cgColor) as CFArray,
                                        locations: nil) else { return }
        let point = CGPoint(x: centre.x * side, y: centre.y * side)
        context.drawRadialGradient(
            gradient,
            startCenter: point, startRadius: 0,
            endCenter: point, endRadius: radius * side,
            options: []
        )
    }

    /// A small noise tile scaled up, rather than a million one-pixel fills.
    private static func grain(_ context: CGContext, _ rect: CGRect, alpha: CGFloat) {
        guard alpha > 0, let tile = noiseTile else { return }
        context.saveGState()
        context.setAlpha(alpha)
        context.setBlendMode(.overlay)
        context.interpolationQuality = .none
        context.draw(tile, in: rect)
        context.restoreGState()
    }

    private static let noiseTile: CGImage? = {
        let side = 160
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for index in stride(from: 0, to: pixels.count, by: 4) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8((seed >> 33) & 0xFF)
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }()
}
