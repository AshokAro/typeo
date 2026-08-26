//
//  GlyphInteraction.swift
//  Typeo
//
//  What a touch (or the phone's own tilt) does to the letters. Every mode is bipolar
//  and rests at 0 doing nothing — see the interaction rules in CLAUDE.md.
//

import Foundation

enum GlyphInteraction: String, CaseIterable, Identifiable {
    case none, warp, attract, gravity, tilt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:    "Off"
        case .warp:    "Warp"
        case .attract: "Attract"
        case .gravity: "Gravity"
        case .tilt:    "Tilt"
        }
    }

    var systemImage: String {
        switch self {
        case .none:    "hand.raised.slash"
        case .warp:    "circle.circle"
        case .attract: "hurricane"
        case .gravity: "arrow.up.arrow.down"
        case .tilt:    "gyroscope"
        }
    }

    var amountLabel: String {
        switch self {
        case .none:    ""
        case .warp:    "Warp"      // negative puckers, positive bloats
        case .attract: "Pull"      // negative pushes away, positive pulls in
        case .gravity: "Gravity"   // negative floats up, positive falls down
        case .tilt:    "Tilt"      // negative rolls uphill, positive rolls downhill
        }
    }

    /// Bipolar controls sit at 0 and do nothing until moved either way.
    var amountRange: ClosedRange<Double> {
        switch self {
        case .none:    0...0
        case .warp:    -1...1
        case .attract: -1...1
        case .gravity: -1...1
        case .tilt:    -1...1
        }
    }

    var defaultAmount: Double {
        switch self {
        case .none:    0
        case .warp:    0
        case .attract: 0
        case .gravity: 0
        case .tilt:    0
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
        case .tilt:
            if value > 0.02 { return "downhill \(Int(value * 100))%" }
            if value < -0.02 { return "uphill \(Int(-value * 100))%" }
            return "level"
        case .none:
            return ""
        }
    }
}
