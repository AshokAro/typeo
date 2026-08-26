//
//  TiltSource.swift
//  Typeo
//
//  Device motion, reduced to one thing the canvas cares about: which way is downhill,
//  in canvas coordinates.
//
//  Measured RELATIVE to how the phone was being held when Tilt was switched on. Nobody
//  holds a phone flat — 45 to 70 degrees back is normal — so absolute gravity would
//  dump every letter into the bottom of the canvas the instant the mode was selected.
//  Capturing a reference pose makes "however you are holding it now" level.
//
//  No usage description is needed for this: only motion ACTIVITY (the pedometer) asks
//  permission, not the accelerometer or gyroscope.
//

import CoreMotion
import CoreGraphics

@MainActor
final class TiltSource {

    /// Downhill direction and steepness, in SpriteKit's axes (x right, y up), each
    /// component clamped to -1...1. Zero when the phone is back in its reference pose.
    private(set) var tilt: CGVector = .zero

    /// Called on the main queue whenever the reading changes, so the scene is pushed to
    /// rather than polled.
    var onUpdate: ((CGVector) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    private let manager = CMMotionManager()
    /// The in-plane gravity vector captured when the mode was switched on.
    private var reference: CGVector?
    /// Hand tremor is always present; below this the canvas should be still.
    private let deadzone: CGFloat = 0.025
    /// Device motion is already filtered, but a little more keeps a settled pile settled.
    private let smoothing: CGFloat = 0.18

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        reference = nil
        tilt = .zero
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.consume(gravity: motion.gravity)
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        reference = nil
        tilt = .zero
        onUpdate?(.zero)
    }

    /// Re-levels to the current pose without interrupting the mode.
    func recalibrate() {
        reference = nil
    }

    private func consume(gravity: CMAcceleration) {
        // The IN-PLANE part of gravity is the slope of the screen. Flat on a table has
        // no in-plane component at all, which is correct: no downhill.
        let inPlane = CGVector(dx: CGFloat(gravity.x), dy: CGFloat(gravity.y))
        guard let reference else {
            self.reference = inPlane
            tilt = .zero
            return
        }

        var dx = inPlane.dx - reference.dx
        var dy = inPlane.dy - reference.dy
        if abs(dx) < deadzone { dx = 0 }
        if abs(dy) < deadzone { dy = 0 }

        let target = CGVector(
            dx: min(max(dx, -1), 1),
            dy: min(max(dy, -1), 1)
        )
        tilt = CGVector(
            dx: tilt.dx + (target.dx - tilt.dx) * smoothing,
            dy: tilt.dy + (target.dy - tilt.dy) * smoothing
        )
        onUpdate?(tilt)
    }
}
