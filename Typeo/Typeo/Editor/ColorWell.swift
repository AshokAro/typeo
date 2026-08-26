//
//  ColorWell.swift
//  Typeo
//
//  SwiftUI's `ColorPicker` draws its own rainbow-ringed well, which reads as a
//  decoration rather than as the colour currently in use. This is the same picker —
//  UIKit's, which is what `ColorPicker` wraps — behind a plain swatch of the actual
//  colour.
//

import SwiftUI
import UIKit

struct ColorWell: View {
    let title: String
    @Binding var color: Color

    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .sheet(isPresented: $isPicking) {
            SystemColorPicker(color: $color)
                .ignoresSafeArea()
                .presentationDetents([.medium, .large])
        }
    }
}

private struct SystemColorPicker: UIViewControllerRepresentable {
    @Binding var color: Color

    func makeCoordinator() -> Coordinator { Coordinator(color: $color) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let controller = UIColorPickerViewController()
        controller.supportsAlpha = false
        controller.selectedColor = UIColor(color)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIColorPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        private let color: Binding<Color>

        init(color: Binding<Color>) { self.color = color }

        // Live, not on dismiss: the canvas behind is the preview.
        func colorPickerViewController(
            _ controller: UIColorPickerViewController,
            didSelect selectedColor: UIColor,
            continuously: Bool
        ) {
            color.wrappedValue = Color(selectedColor)
        }
    }
}
