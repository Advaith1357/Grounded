//
//  CircuitBackdrop.swift
//  Grounded
//
//  The faint circuit-board wire/node pattern that sits behind every Nexus
//  screen. Recreated with plain Shapes (the source SVGs are just straight
//  lines and small squares) rather than downloaded assets — there's no real
//  vector art to reproduce here, only geometry.
//
//  Simplification: the Figma file also has a per-screen "active wire" glow
//  highlighting a path relevant to that screen's state. This shared backdrop
//  only reproduces the common static wiring, not those bespoke per-screen
//  accents — a reasonable cut for a decorative background layer.
//

import SwiftUI

struct CircuitBackdrop: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            verticalWire(x: 40, y1: 100, y2: 300)
            horizontalWire(y: 300, x1: 40, x2: 80)
            verticalWire(x: 80, y1: 340, y2: 490)
            verticalWire(x: 340, y1: 150, y2: 450)
            horizontalWire(y: 450, x1: 300, x2: 340)

            node(x: 35, y: 95)
            node(x: 335, y: 145)
            node(x: 75, y: 485)
        }
        .allowsHitTesting(false)
        .clipped()
    }

    private func verticalWire(x: CGFloat, y1: CGFloat, y2: CGFloat) -> some View {
        Rectangle()
            .fill(NexusColor.border)
            .frame(width: 1, height: y2 - y1)
            .offset(x: x, y: y1)
    }

    private func horizontalWire(y: CGFloat, x1: CGFloat, x2: CGFloat) -> some View {
        Rectangle()
            .fill(NexusColor.border)
            .frame(width: x2 - x1, height: 1)
            .offset(x: x1, y: y)
    }

    private func node(x: CGFloat, y: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(hex: 0x222222))
            .frame(width: 10, height: 10)
            .offset(x: x, y: y)
    }
}
