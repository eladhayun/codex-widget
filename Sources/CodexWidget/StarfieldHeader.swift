import SwiftUI

/// A quiet, decorative star field; the title is separate from tab navigation.
struct StarfieldHeader: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        Text("Codex Widget")
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 42)
            .background {
                TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion || !visible)) { timeline in
                    Canvas { context, size in
                        let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                        for index in 0..<48 {
                            // Stable positions avoid flicker when SwiftUI redraws the header.
                            let seed = Double(index)
                            let phase = seed * 2.399963
                            let speed = 0.0015 + Double(index % 4) * 0.0004
                            let x = (seed * 0.618034 + time * speed).truncatingRemainder(dividingBy: 1) * size.width
                            let y = (seed * 0.414214 + 0.17).truncatingRemainder(dividingBy: 1) * size.height
                            let brightness = 0.20 + 0.20 * (1 + sin(time * 0.65 + phase)) / 2
                            // Keep stars subdued under the title for clear text in either theme.
                            let titleFade = x < 155 ? 0.25 : 1.0
                            let side = index % 7 == 0 ? 1.5 : 1.0
                            context.fill(Path(CGRect(x: x, y: y, width: side, height: side)),
                                         with: .color(color.opacity(brightness * titleFade)))
                        }
                    }
                }
                .background(color.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isHeader)
            .onAppear { visible = true }
            .onDisappear { visible = false }
    }
}
