import AppKit
import SwiftUI

/// Bridges `NSVisualEffectView` so views can request a specific system
/// material. Used sparingly — the sidebar and toolbar already carry the right
/// treatment from the system, and painting over them fights it.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
