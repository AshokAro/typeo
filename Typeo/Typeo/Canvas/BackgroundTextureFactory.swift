//
//  BackgroundTextureFactory.swift
//  Typeo
//
//  The background as a node and as a texture. Both, because the glass shader has to
//  SAMPLE what is behind the letters and a solid-colour node has no texture to sample.
//

import SpriteKit
import SwiftUI
import UIKit

enum BackgroundTextureFactory {
    static func node(for background: Background, size: CGSize) -> SKSpriteNode {
        switch background {
        case let .solid(rgba):
            return SKSpriteNode(color: UIColor(rgba.color), size: size)

        case .linearGradient, .image:
            return SKSpriteNode(texture: texture(for: background, size: size), size: size)
        }
    }

    /// The same pixels as `node`, as a texture — the glass shader has to SAMPLE the
    /// background, and a solid colour node has no texture to sample.
    static func texture(for background: Background, size: CGSize) -> SKTexture {
        switch background {
        case let .image(id):
            // A missing file falls back to black rather than an empty canvas: the photo
            // lives outside the composition, so it can go away independently.
            return BackgroundImageStore.texture(for: id, size: size)
                ?? texture(for: .solid(.black), size: size)

        case let .solid(rgba):
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let small = CGSize(width: 8, height: 8)
            let image = UIGraphicsImageRenderer(size: small, format: format).image { context in
                UIColor(rgba.color).setFill()
                context.fill(CGRect(origin: .zero, size: small))
            }
            return SKTexture(image: image)

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
            return SKTexture(image: image)
        }
    }
}
