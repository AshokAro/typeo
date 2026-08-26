//
//  WidgetTimelinePlan.swift
//  Typeo
//
//  The widget's rotation schedule, as pure logic.
//
//  It lives here rather than inside the extension so it compiles and is verified today,
//  while the extension target is still blocked on a paid Apple Developer account. The
//  extension's getTimeline does nothing but map these slots into TimelineEntry values.
//

import Foundation

enum WidgetTimelinePlan {

    struct Slot: Hashable {
        var date: Date
        var entry: WidgetEntryPayload?
    }

    struct Plan: Hashable {
        var slots: [Slot]
        /// When WidgetKit should ask for a fresh timeline.
        var reloadAfter: Date
    }

    /// WidgetKit treats a timeline as a budget, so refreshing faster than roughly a
    /// quarter of an hour is not honoured. Clamp rather than pretend.
    static let minimumRotationMinutes = 15

    static func plan(for manifest: WidgetManifest, startingAt start: Date) -> Plan {
        guard !manifest.entries.isEmpty else {
            return Plan(
                slots: [Slot(date: start, entry: nil)],
                reloadAfter: start.addingTimeInterval(60 * 60)
            )
        }

        let minutes = max(minimumRotationMinutes, manifest.rotationMinutes)
        let step = TimeInterval(minutes * 60)

        var slots: [Slot] = []
        var date = start
        for entry in manifest.entries {
            slots.append(Slot(date: date, entry: entry))
            date = date.addingTimeInterval(step)
        }
        return Plan(slots: slots, reloadAfter: date)
    }
}
