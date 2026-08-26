//
//  KeyInputBridge.swift
//  Typeo
//
//  Raw keyboard input for in-canvas editing.
//
//  A UITextField would fight us: we need the insertion point to live on the canvas,
//  not in a hidden field whose own selection we would have to mirror. UIKeyInput gives
//  exactly the two callbacks that matter — insertText and deleteBackward — and leaves
//  the caret entirely to us.
//
//  Trade-off: no autocorrect, no dictation. For a typography canvas that is the right
//  side of the trade.
//

import SwiftUI
import UIKit

final class KeyInputView: UIView, UIKeyInput {
    var onInsert: ((String) -> Void)?
    var onDelete: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    // MARK: UIKeyInput
    var hasText: Bool { true }          // keeps the delete key live even when empty
    func insertText(_ text: String) { onInsert?(text) }
    func deleteBackward() { onDelete?() }

    // MARK: UITextInputTraits
    var keyboardAppearance: UIKeyboardAppearance = .dark
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var returnKeyType: UIReturnKeyType = .default
}

struct KeyInputBridge: UIViewRepresentable {
    @Binding var isEditing: Bool
    let onInsert: (String) -> Void
    let onDelete: () -> Void

    func makeUIView(context: Context) -> KeyInputView {
        let view = KeyInputView()
        view.isUserInteractionEnabled = false   // taps are handled by the SpriteKit scene
        view.onInsert = onInsert
        view.onDelete = onDelete
        return view
    }

    func updateUIView(_ view: KeyInputView, context: Context) {
        view.onInsert = onInsert
        view.onDelete = onDelete

        DispatchQueue.main.async {
            if isEditing, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !isEditing, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }
}
