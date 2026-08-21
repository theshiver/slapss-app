//
//  MeshBackground.swift
//  slapss
//
//  Animated mesh-gradient backdrop. Three blurred radial blobs drift across
//  the canvas on long, offset cycles so the motion feels organic — no
//  mechanical pulses or sweeps. Colors are chosen by Palette and react to
//  the alert state (e.g. switch to "urgent" when the meeting is late).
//

import SwiftUI

struct MeshBackground: View {
    enum Palette {
        case warm, cool, sunset, forest, urgent

        fileprivate var colors: [Color] {
            switch self {
            case .warm:
                return [Color(rgb: 0xc97a3a), Color(rgb: 0x6b4a8a), Color(rgb: 0x3a5a8a)]
            case .cool:
                return [Color(rgb: 0x2d6cb0), Color(rgb: 0x5a3a8a), Color(rgb: 0x3a8a7a)]
            case .sunset:
                return [Color(rgb: 0xe06b3a), Color(rgb: 0xa83a6b), Color(rgb: 0x5a3a8a)]
            case .forest:
                return [Color(rgb: 0x3a8a5a), Color(rgb: 0x2d6c5a), Color(rgb: 0x5a6c3a)]
            case .urgent:
                return [Color(rgb: 0xd04a3a), Color(rgb: 0x8a3a3a), Color(rgb: 0x6b2d3a)]
            }
        }
    }

    let palette: Palette
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let colors = palette.colors

            ZStack {
                Color(rgb: 0x0c0c10)

                // Three blobs cluster around the center of the canvas so the
                // glass card (which sits in the middle of the screen) gets a
                // colorful backdrop instead of being marooned in dark space.
                // Each blob has its own offset cycle so the motion stays
                // organic and never aligns into an obvious pulse.

                // Upper-left of center — orange. 22s cycle.
                blob(color: colors[0], size: max(w, h) * 0.85)
                    .position(
                        x: animate ? w * 0.30 : w * 0.40,
                        y: animate ? h * 0.35 : h * 0.45
                    )
                    .animation(.easeInOut(duration: 22).repeatForever(autoreverses: true), value: animate)

                // Lower-right of center — magenta/purple. 28s cycle.
                blob(color: colors[1], size: max(w, h) * 0.75)
                    .position(
                        x: animate ? w * 0.70 : w * 0.60,
                        y: animate ? h * 0.65 : h * 0.55
                    )
                    .animation(.easeInOut(duration: 28).repeatForever(autoreverses: true), value: animate)

                // Center accent — third color, slightly smaller for layering.
                // 32s cycle drifts horizontally so the central highlight shifts.
                blob(color: colors[2], size: max(w, h) * 0.55, opacity: 0.7)
                    .position(
                        x: animate ? w * 0.45 : w * 0.55,
                        y: animate ? h * 0.50 : h * 0.45
                    )
                    .animation(.easeInOut(duration: 32).repeatForever(autoreverses: true), value: animate)
            }
            .compositingGroup()
            // Blobs stay frozen at their start positions when Reduce Motion is enabled.
            .onAppear { if !reduceMotion { animate = true } }
        }
    }

    /// A blurred radial blob. Default opacity 0.85 matches the reference design;
    /// the 65%-radius transparent stop combined with .blur produces the soft
    /// "mesh" feel without the colors washing out.
    private func blob(color: Color, size: CGFloat, opacity: Double = 0.85) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: color.opacity(opacity), location: 0),
                        .init(color: color.opacity(0), location: 0.65),
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 60)
    }
}

extension Color {
    /// Convenience init for hex like `0xRRGGBB`.
    init(rgb: UInt32, alpha: Double = 1.0) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: alpha
        )
    }
}
