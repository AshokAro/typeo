//
//  WidgetCompositionView.swift
//  Typeo
//
//  The view the widget renders. Lives in the app target so it compiles and can be
//  previewed today; add this same file to the widget extension target when it is
//  created (see TypeoWidget/README.md).
//
//  Deliberately depends on nothing but the payload and a UIImage — no SpriteKit, no
//  Metal, no store. A widget process has a tight memory budget and cannot run the
//  live canvas.
//

import SwiftUI

struct WidgetCompositionView: View {
    let entry: WidgetEntryPayload?
    let image: UIImage?

    var body: some View {
        ZStack {
            Color.black

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .clipped()
        .accessibilityLabel(accessibilityText)
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "textformat")
                .font(.system(size: 22, weight: .light))
            Text("Pin a composition")
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.4))
        .padding(8)
    }

    private var accessibilityText: String {
        guard let entry, !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No composition pinned"
        }
        return entry.text
    }
}
