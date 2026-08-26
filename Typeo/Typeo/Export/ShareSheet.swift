//
//  ShareSheet.swift
//  Typeo
//
//  Generic UIActivityViewController — reaches Instagram, Messages, AirDrop, Files and
//  everything else with no per-app integration. See CLAUDE.md's export decision.
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
