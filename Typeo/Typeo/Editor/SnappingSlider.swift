//
//  SnappingSlider.swift
//  Typeo
//
//  Every bipolar control rests at 0 and does nothing there (CLAUDE.md), so 0 has to
//  be findable without looking. SwiftUI's Slider has no detent of its own: the dead
//  zone is applied in the binding, and a haptic fires on the way in so it is felt
//  rather than hunted for.
//

import SwiftUI
import UIKit

struct SnappingSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    /// Half-width of the dead zone, in slider units.
    private let catchRadius = 0.05

    private var isBipolar: Bool { range.lowerBound < 0 }
    @State private var wasCaught = false

    var body: some View {
        ZStack {
            if isBipolar {
                // The centre tick, so it is obvious the control rests at zero.
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1, height: 12)
            }
            Slider(value: snapped, in: range)
        }
    }

    private var snapped: Binding<Double> {
        Binding(
            get: { value },
            set: { raw in
                guard isBipolar else { value = raw; return }
                if abs(raw) <= catchRadius {
                    if !wasCaught {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        wasCaught = true
                    }
                    value = 0
                } else {
                    wasCaught = false
                    value = raw
                }
            }
        )
    }
}
