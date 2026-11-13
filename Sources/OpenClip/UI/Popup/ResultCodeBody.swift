// ResultCodeBody.swift
// OpenClip
//
// Monospaced body for extension results declared as code. Display-only: copy, paste and drag keep
// using payload.text, so the code leaves the card unchanged.
import SwiftUI

struct ResultCodeBody: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
