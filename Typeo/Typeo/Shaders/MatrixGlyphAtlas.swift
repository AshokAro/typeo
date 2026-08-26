//
//  MatrixGlyphAtlas.swift
//  Typeo
//
//  The Matrix rain needs actual CHARACTERS, and a fragment shader cannot draw type.
//  So the characters are drawn once into an 8x8 texture atlas and handed to the shader,
//  which picks a cell per grid square. Without this the rain is only lit blocks.
//

import SpriteKit
import UIKit

enum MatrixGlyphAtlas {

    /// 8x8. The shader hardcodes 8 as well — changing it means changing both.
    static let columns = 8
    static let count = columns * columns

    /// Half-width katakana, digits and a few latin forms: the film's alphabet is
    /// mostly mirrored katakana, and these read correctly at cell size.
    private static let characters: [String] = {
        let katakana = "ﾊﾐﾋｰｳｼﾅﾓﾆｻﾜﾂｵﾘｱﾎﾃﾏｹﾒｴｶｷﾑﾕﾗｾﾈｽﾀﾇﾍｦｲｸｺｿﾁﾄﾉﾌﾔﾖﾙﾚﾛﾝ"
        let rest = "0123456789:.=*+-<>¦"
        let all = Array(katakana + rest).map(String.init)
        return Array(all.prefix(count))
    }()

    static let texture: SKTexture = {
        let cell: CGFloat = 64
        let side = cell * CGFloat(columns)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let font = UIFont.monospacedSystemFont(ofSize: cell * 0.78, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                // White: the shader tints it. Colour never has to be baked in.
                .foregroundColor: UIColor.white,
            ]
            for (index, character) in characters.enumerated() {
                let column = CGFloat(index % columns)
                // Row 0 at the BOTTOM, matching SKTexture's coordinate space, so the
                // shader's cell index maps straight through.
                let row = CGFloat(columns - 1 - index / columns)
                let string = character as NSString
                let size = string.size(withAttributes: attributes)
                let origin = CGPoint(
                    x: column * cell + (cell - size.width) / 2,
                    y: row * cell + (cell - size.height) / 2
                )
                string.draw(at: origin, withAttributes: attributes)
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()
}
