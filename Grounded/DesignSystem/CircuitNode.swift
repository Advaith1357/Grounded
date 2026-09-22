//
//  CircuitNode.swift
//  Grounded
//
//  Home's central visual — a denser, more organic PCB fan-out than the
//  original 8-spoke version: traces attach at many points around the ring
//  (not just the 8 cardinal/diagonal axes) but each still travels in a single
//  hard 45°-multiple compass direction once it leaves the ring, the way a
//  real chip's fan-out routing snaps onto the grid. Round vias at the tips
//  instead of square pads, occasional T-branch taps for density, and a
//  faint radial fill so the ring reads as a chip rather than a bare outline.
//
//  `isCharging` drives a traveling brightness pulse along every trace: when
//  grounded (charging), the pulse travels from each trace's outer tip back
//  toward the ring; when unlocked (discharging), it travels from the ring
//  out to the tip.
//

import SwiftUI

struct CircuitNode: View {
    var diameter: CGFloat = 200
    var color: Color = NexusColor.accent
    var isCharging: Bool = true

    private let padSize: CGFloat = 5
    private let pulsePeriod: Double = 2.4
    private let traceCount = 16
    private let runLengths: [CGFloat] = [34, 20, 42, 26, 16, 38, 22, 46]

    private struct TraceSpec {
        let attachDegrees: Double
        let routeDegrees: Double
        let runLength: CGFloat
        let hasBranch: Bool
    }

    private var traces: [TraceSpec] {
        (0..<traceCount).map { i in
            let attach = Double(i) * (360.0 / Double(traceCount))
            let route = (attach / 45.0).rounded() * 45.0
            return TraceSpec(
                attachDegrees: attach,
                routeDegrees: route,
                runLength: runLengths[i % runLengths.count],
                hasBranch: i % 3 == 0
            )
        }
    }

    private var maxRunLength: CGFloat { runLengths.max() ?? 0 }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = diameter / 2
                let time = timeline.date.timeIntervalSinceReferenceDate
                let travel = travelPosition(at: time)
                let ring = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

                context.fill(
                    Path(ellipseIn: ring),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.14), .clear]),
                        center: center, startRadius: 0, endRadius: radius
                    )
                )

                for spec in traces {
                    drawTrace(in: &context, center: center, radius: radius, spec: spec, travel: travel)
                }

                context.stroke(Path(ellipseIn: ring), with: .color(color), lineWidth: 2)
            }
        }
        .frame(
            width: diameter + maxRunLength * 2 + 12,
            height: diameter + maxRunLength * 2 + 12
        )
        .shadow(color: color.opacity(0.25), radius: 12)
    }

    /// 0 = pulse sitting at the ring (inner end), 1 = pulse sitting at the
    /// outermost tip. Charging sweeps 1 -> 0 (energy flowing inward);
    /// discharging sweeps 0 -> 1 (energy flowing outward).
    private func travelPosition(at time: Double) -> Double {
        let phase = (time.truncatingRemainder(dividingBy: pulsePeriod)) / pulsePeriod
        return isCharging ? (1 - phase) : phase
    }

    private func bump(at t: Double, travel: Double) -> Double {
        let sigma = 0.22
        let amplitude = 0.55
        let delta = t - travel
        return amplitude * exp(-(delta * delta) / (2 * sigma * sigma))
    }

    private func pulseGradient(baseOpacity: Double, travel: Double) -> Gradient {
        let stopCount = 8
        let stops = (0...stopCount).map { i -> Gradient.Stop in
            let t = Double(i) / Double(stopCount)
            let opacity = min(1.0, baseOpacity + bump(at: t, travel: travel))
            return Gradient.Stop(color: color.opacity(opacity), location: t)
        }
        return Gradient(stops: stops)
    }

    /// A trace leaves the ring at `attachDegrees` (any of the 16 evenly
    /// spaced points) but immediately runs in a single straight line along
    /// `routeDegrees` — the nearest 45°-multiple compass direction — ending
    /// in a round via. About a third of traces get a short perpendicular
    /// branch tap partway along for extra density.
    private func drawTrace(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, spec: TraceSpec, travel: Double) {
        let attachRad = Angle(degrees: spec.attachDegrees).radians
        let adx = cos(attachRad)
        let ady = sin(attachRad)
        let start = CGPoint(x: center.x + adx * radius, y: center.y + ady * radius)

        let routeRad = Angle(degrees: spec.routeDegrees).radians
        let rdx = cos(routeRad)
        let rdy = sin(routeRad)
        let end = CGPoint(x: start.x + rdx * spec.runLength, y: start.y + rdy * spec.runLength)

        var main = Path()
        main.move(to: start)
        main.addLine(to: end)
        context.stroke(main, with: .linearGradient(pulseGradient(baseOpacity: 0.65, travel: travel), startPoint: start, endPoint: end), lineWidth: 1.3)

        let tipOpacity = min(1.0, 0.85 + bump(at: 1.0, travel: travel))
        context.fill(via(at: end), with: .color(color.opacity(tipOpacity)))

        guard spec.hasBranch else { return }
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let perp = (dx: -rdy, dy: rdx)
        let branchLength: CGFloat = 10
        let branchEnd = CGPoint(x: mid.x + perp.dx * branchLength, y: mid.y + perp.dy * branchLength)
        let branchOpacity = min(1.0, 0.5 + bump(at: 0.5, travel: travel))

        var branch = Path()
        branch.move(to: mid)
        branch.addLine(to: branchEnd)
        context.stroke(branch, with: .color(color.opacity(branchOpacity)), lineWidth: 1.1)
        context.fill(via(at: branchEnd, size: padSize * 0.6), with: .color(color.opacity(branchOpacity)))
    }

    private func via(at point: CGPoint, size: CGFloat? = nil) -> Path {
        let s = size ?? padSize
        return Path(ellipseIn: CGRect(x: point.x - s / 2, y: point.y - s / 2, width: s, height: s))
    }
}

#if DEBUG
#Preview("Charging") {
    CircuitNode(isCharging: true)
        .padding(60)
        .background(NexusColor.background)
}

#Preview("Discharging") {
    CircuitNode(isCharging: false)
        .padding(60)
        .background(NexusColor.background)
}
#endif
