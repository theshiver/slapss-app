//
//  VisualEffectView.swift
//  slapss
//
//  SwiftUI wrapper around NSVisualEffectView. The card on the alert overlay
//  uses this with `.withinWindow` blending so the frosted glass effect blurs
//  the mesh gradient sitting beneath it inside the same window.
//

import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var emphasized: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = emphasized
    }
}
