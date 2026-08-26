//
//  SplashView.swift
//  Typeo
//
//  Static, ~1s, no loading logic — the app is local-only, there is nothing to load.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(verbatim: "Typeo")
                .font(.system(size: 64, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
                .kerning(-2)
        }
    }
}

#Preview {
    SplashView()
}
