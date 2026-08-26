//
//  ToolRail.swift
//  Typeo
//
//  The floating control rail. Draggable, so it can be moved off whatever it is
//  covering — the whole point of putting controls beside the canvas rather than in a
//  sheet was to keep the artwork visible.
//

import SwiftUI

enum ToolRailItem: Hashable {
    case textFill, backgroundFill, font, style, lock
}

struct ToolRail: View {
    let store: CompositionStore
    @Binding var activeFill: FillTarget?
    @Binding var isLocked: Bool
    /// Position is remembered for the session so it stays where it was put.
    @Binding var offset: CGSize
    let bounds: CGSize

    @GestureState private var drag: CGSize = .zero

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    activeFill = activeFill == .text ? nil : .text
                }
            } label: {
                FillChip(paint: paint(for: .text), isSelected: activeFill == .text, glyph: "A")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Text colour")

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    activeFill = activeFill == .background ? nil : .background
                }
            } label: {
                FillChip(paint: paint(for: .background), isSelected: activeFill == .background)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Background colour")

            divider

            Button {
                isLocked.toggle()
            } label: {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 26)
                    .foregroundStyle(isLocked ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLocked ? "Unlock effect" : "Lock effect in place")

            // The drag lives on THIS handle alone. Attached to the whole rail it
            // intercepted every touch, so the buttons inside stopped responding and
            // the tap fell through to the canvas behind.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 20)
                .contentShape(.rect)
                .gesture(
                    DragGesture()
                        .updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            let limitX = bounds.width * 0.42
                            let limitY = bounds.height * 0.42
                            offset.width = min(max(offset.width + value.translation.width, -limitX), limitX)
                            offset.height = min(max(offset.height + value.translation.height, -limitY), limitY)
                        }
                )
                .accessibilityLabel("Drag to move the controls")
        }
        .padding(7)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .fixedSize()
        // Solid hit area, so a tap on the rail never reaches the canvas behind it.
        .contentShape(.rect(cornerRadius: 22))
        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 20, height: 1)
    }

    private func paint(for target: FillTarget) -> FillPreview {
        switch target {
        case .text:
            if let gradient = store.textGradient { return .gradient(gradient) }
            return .solid(store.style.color)
        case .background:
            if let gradient = store.backgroundGradient { return .gradient(gradient) }
            if case let .solid(rgba) = store.composition.background { return .solid(rgba) }
            return .solid(.black)
        }
    }
}
