//
//  TypeoWidget.swift
//  TypeoWidget
//
//  v5 widget extension. NOT COMPILED YET — this folder is deliberately outside the
//  app target's synchronized group. See README.md in this folder for how to add the
//  target, which needs a paid Apple Developer Program membership for the App Group.
//
//  Everything this file depends on already exists and is verified in the app target:
//    TypeoSharedStore, WidgetPayload, WidgetTimelinePlan, WidgetCompositionView
//  Add those three files to this target's membership when you create it.
//
//  A widget CANNOT run the shader or physics canvas — it renders a finished PNG that
//  the app produced when you pinned the composition.
//

import WidgetKit
import SwiftUI

struct TypeoEntry: TimelineEntry {
    let date: Date
    let payload: WidgetEntryPayload?
    let image: UIImage?
}

struct TypeoProvider: TimelineProvider {

    func placeholder(in context: Context) -> TypeoEntry {
        TypeoEntry(date: .now, payload: nil, image: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TypeoEntry) -> Void) {
        let manifest = TypeoSharedStore.loadManifest()
        let first = manifest.entries.first
        completion(TypeoEntry(date: .now, payload: first, image: first.flatMap(loadImage)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TypeoEntry>) -> Void) {
        // All the scheduling logic lives in WidgetTimelinePlan, which is compiled and
        // verified in the app target. This just loads the images.
        let plan = WidgetTimelinePlan.plan(
            for: TypeoSharedStore.loadManifest(),
            startingAt: .now
        )
        let entries = plan.slots.map { slot in
            TypeoEntry(
                date: slot.date,
                payload: slot.entry,
                image: slot.entry.flatMap(loadImage)
            )
        }
        completion(Timeline(entries: entries, policy: .after(plan.reloadAfter)))
    }

    private func loadImage(_ payload: WidgetEntryPayload) -> UIImage? {
        UIImage(contentsOfFile: TypeoSharedStore.imageURL(named: payload.imageFileName).path)
    }
}

struct TypeoWidgetEntryView: View {
    var entry: TypeoProvider.Entry

    var body: some View {
        WidgetCompositionView(entry: entry.payload, image: entry.image)
            .containerBackground(.black, for: .widget)
    }
}

@main
struct TypeoWidget: Widget {
    let kind = "TypeoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TypeoProvider()) { entry in
            TypeoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Typeo")
        .description("Shows a composition you pinned in the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
