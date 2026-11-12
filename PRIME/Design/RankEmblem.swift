import SwiftUI

/// Original PRIME rank emblems. One crest language, gaining ornament with each tier:
/// outline → chevrons → faceted crest → gem → wings → crown.
struct RankEmblem: View {
    let tier: RankTier
    var size: CGFloat = 44
    var dimmed = false
    /// Adds a living glow (and a slow shimmer on Master) when motion allows.
    var animated = false
    /// Draws the tier's coloured aura behind the emblem. On by default from 56pt up.
    var aura: Bool? = nil

    @Environment(\.motion) private var motion
    @State private var breathe = false

    private var showsAura: Bool { (aura ?? (size >= 56)) && !dimmed && tier != .unranked }

    var body: some View {
        Canvas { context, canvasSize in
            EmblemArt.draw(tier, in: &context, size: canvasSize)
        }
        .frame(width: size, height: size)
        .modifier(MasterShimmer(active: animated && tier == .master && !dimmed))
        .background {
            if showsAura {
                RadialGradient(colors: [tier.glow.opacity(breathe ? 0.5 : 0.32), tier.glow.opacity(0.08), .clear],
                               center: .center, startRadius: size * 0.1, endRadius: size * 0.75)
                    .frame(width: size * 1.5, height: size * 1.5)
                    .blur(radius: size * 0.08)
            }
        }
        .saturation(dimmed ? 0 : 1)
        .opacity(dimmed ? 0.4 : 1)
        .shadow(color: dimmed ? .clear : tier.glow.opacity(tier >= .elite ? (breathe ? 0.7 : 0.4) : 0.3),
                radius: size / (tier >= .elite ? 5 : 9), y: size / 30)
        .shadow(color: dimmed ? .clear : .black.opacity(0.35), radius: size / 14, y: size / 18)
        .onAppear {
            guard animated, motion.allowsMovement, !dimmed, tier >= .gold else { return }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityElement()
        .accessibilityLabel(dimmed ? "\(tier.name), not reached" : "\(tier.name) rank")
    }
}

private struct MasterShimmer: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.shimmer(repeats: true, color: Color(hex: 0xFFF1C0)) } else { content }
    }
}

enum EmblemArt {
    // Geometry in a 100 × 112 design box; the canvas maps -10…110 × -8…112 onto the view.
    private static let crest = SVGPath.parse("M50,6 L88,19 L88,52 C88,77 71,95 50,106 C29,95 12,77 12,52 L12,19 Z")
    private static let crestInner = SVGPath.parse("M50,15 L80,25 L80,52 C80,72 67,86 50,96 C33,86 20,72 20,52 L20,25 Z")
    private static let hexa = SVGPath.parse("M50,4 L90,24 L90,64 L50,108 L10,64 L10,24 Z")
    private static let hexaInner = SVGPath.parse("M50,14 L81,30 L81,61 L50,96 L19,61 L19,30 Z")
    private static let gem = SVGPath.parse("M50,4 L94,44 L50,108 L6,44 Z")
    private static let gemFacets = SVGPath.parse("M6,44 L94,44 M28,24 L38,44 L50,108 L62,44 L72,24 M38,44 L50,4 L62,44")
    private static let gemTable = SVGPath.parse("M50,4 L72,24 L62,44 L38,44 L28,24 Z")
    private static let wingLeft = SVGPath.parse("M14,30 C2,32 -6,44 -8,58 C-2,54 4,52 10,52 C2,58 -2,66 -2,74 C4,68 10,66 15,66 C10,72 8,78 9,84 C14,78 19,74 24,72 Z")
    private static let wingRight = wingLeft.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100, ty: 0))
    private static let crown = SVGPath.parse("M30,14 L34,-2 L42,8 L50,-6 L58,8 L66,-2 L70,14 Z")
    private static let laurels = SVGPath.parse("M26,92 C30,100 40,106 50,108 M74,92 C70,100 60,106 50,108")
    private static let masterGem = SVGPath.parse("M50,36 L64,54 L50,76 L36,54 Z")
    private static let masterGemFacets = SVGPath.parse("M50,36 L57,54 L50,76 L43,54 Z M36,54 L64,54")
    private static let unrankedMark = SVGPath.parse("M42,56 L50,48 L58,56 L50,64 Z")

    private static func chevron(y: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 28, y: y))
        path.addLine(to: CGPoint(x: 50, y: y + 14))
        path.addLine(to: CGPoint(x: 72, y: y))
        path.addLine(to: CGPoint(x: 72, y: y + 7))
        path.addLine(to: CGPoint(x: 50, y: y + 21))
        path.addLine(to: CGPoint(x: 28, y: y + 7))
        path.closeSubpath()
        return path
    }

    private static func star(center: CGPoint, outer: CGFloat, inner: CGFloat, points: Int) -> Path {
        var path = Path()
        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(points)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func gradient(_ colors: [Color]) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 10, y: 0), endPoint: CGPoint(x: 92, y: 110))
    }

    /// Fills a shape as a bevelled metal plate: body gradient, a lit top-left edge, a shaded
    /// bottom-right edge and a diagonal sheen.
    private static func metal(_ shape: Path, fill: GraphicsContext.Shading, line: CGFloat, in context: inout GraphicsContext) {
        context.fill(shape, with: fill)
        context.drawLayer { layer in
            layer.clip(to: shape)
            // Bevel: a thick stroke that is light at the top-left and dark at the bottom-right.
            layer.stroke(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.75), .white.opacity(0.1), .black.opacity(0.1), .black.opacity(0.55)]),
                                                      startPoint: CGPoint(x: 10, y: 0), endPoint: CGPoint(x: 90, y: 110)),
                         lineWidth: line * 4)
            // Sheen: a soft diagonal band of light across the upper half.
            var band = Path()
            band.move(to: CGPoint(x: -20, y: 40))
            band.addLine(to: CGPoint(x: 70, y: -30))
            band.addLine(to: CGPoint(x: 110, y: 0))
            band.addLine(to: CGPoint(x: 10, y: 80))
            band.closeSubpath()
            layer.fill(band, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.26), .white.opacity(0)]),
                                                   startPoint: CGPoint(x: 0, y: 70), endPoint: CGPoint(x: 70, y: 0)))
        }
    }

    static func draw(_ tier: RankTier, in context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width, size.height) / 120
        context.translateBy(x: (size.width - 120 * scale) / 2, y: (size.height - 120 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 10, y: 8)
        let line = max(0.8, 1.4 / max(scale, 0.3))
        let rim = GraphicsContext.Shading.color(.white.opacity(0.4))
        let fill = gradient(tier.gradientStops)

        switch tier {
        case .unranked:
            context.fill(crest, with: .color(Color(hex: 0x0E1626)))
            context.stroke(crest, with: .color(Color(hex: 0x4A5872)), style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
            context.fill(unrankedMark, with: .color(Color(hex: 0x4A5872)))

        case .bronze, .silver, .gold:
            metal(crest, fill: fill, line: line, in: &context)
            context.fill(crestInner, with: .color(.black.opacity(0.22)))
            context.stroke(crestInner, with: .color(.white.opacity(0.18)), lineWidth: line * 0.6)
            let chevronFill: Color = tier == .bronze ? Color(hex: 0xFFD9B8) : (tier == .silver ? .white : Color(hex: 0xFFF6CC))
            let rows: [CGFloat] = tier == .bronze ? [44] : (tier == .silver ? [36, 54] : [32, 47, 62])
            for y in rows {
                let chevron = chevron(y: y)
                context.fill(chevron, with: .color(chevronFill))
                context.stroke(chevron, with: .color(.black.opacity(0.25)), lineWidth: line * 0.7)
            }
            if tier == .gold { context.fill(star(center: CGPoint(x: 50, y: 22), outer: 6, inner: 2.6, points: 5), with: .color(Color(hex: 0xFFF7D0))) }
            context.stroke(crest, with: rim, lineWidth: line)

        case .platinum:
            metal(hexa, fill: fill, line: line, in: &context)
            context.fill(hexaInner, with: .color(.black.opacity(0.2)))
            var spokes = Path()
            for point in [CGPoint(x: 50, y: 14), CGPoint(x: 81, y: 30), CGPoint(x: 81, y: 61), CGPoint(x: 50, y: 96), CGPoint(x: 19, y: 61), CGPoint(x: 19, y: 30)] {
                spokes.move(to: CGPoint(x: 50, y: 54))
                spokes.addLine(to: point)
            }
            context.stroke(spokes, with: .color(.white.opacity(0.35)), lineWidth: line * 0.8)
            context.fill(star(center: CGPoint(x: 50, y: 54), outer: 17, inner: 6, points: 4), with: .color(Color(hex: 0xF4FFFD)))
            context.stroke(hexa, with: .color(.white.opacity(0.55)), lineWidth: line)

        case .diamond:
            metal(gem, fill: fill, line: line, in: &context)
            context.fill(gemTable, with: .color(.white.opacity(0.25)))
            context.stroke(gemFacets, with: .color(.white.opacity(0.45)), lineWidth: line * 0.9)
            context.stroke(gem, with: .color(.white.opacity(0.6)), lineWidth: line)

        case .elite:
            for wing in [wingLeft, wingRight] {
                metal(wing, fill: fill, line: line * 0.6, in: &context)
            }
            metal(crest, fill: fill, line: line, in: &context)
            context.fill(crestInner, with: .color(.black.opacity(0.25)))
            context.fill(star(center: CGPoint(x: 50, y: 55), outer: 20, inner: 8, points: 5), with: .color(Color(hex: 0xEFE8FF)))
            context.stroke(crest, with: .color(.white.opacity(0.45)), lineWidth: line)

        case .master:
            let gold = gradient([Color(hex: 0xFFEFB0), Color(hex: 0xF2B33D), Color(hex: 0x9A5A05)])
            context.fill(Path(ellipseIn: CGRect(x: -8, y: -2, width: 116, height: 116)),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0xFF8A3D).opacity(0.5), .clear]),
                                               center: CGPoint(x: 50, y: 56), startRadius: 0, endRadius: 58))
            metal(wingLeft, fill: gold, line: line * 0.6, in: &context)
            metal(wingRight, fill: gold, line: line * 0.6, in: &context)
            metal(crown, fill: gold, line: line * 0.6, in: &context)
            metal(crest, fill: gradient([Color(hex: 0x3A1023), Color(hex: 0x0E0207)]), line: line, in: &context)
            context.stroke(crest, with: gold, lineWidth: 4)
            context.stroke(crest, with: .color(.white.opacity(0.35)), lineWidth: line * 0.7)
            context.stroke(crestInner, with: .color(Color(hex: 0xF2B33D).opacity(0.6)), lineWidth: line)
            context.fill(masterGem, with: gradient([Color(hex: 0xFFB0A0), Color(hex: 0xFF4D5E), Color(hex: 0x8E0B24)]))
            context.stroke(masterGem, with: .color(Color(hex: 0xFFE7A0)), lineWidth: line)
            context.stroke(masterGemFacets, with: .color(.white.opacity(0.4)), lineWidth: line * 0.7)
            context.stroke(laurels, with: gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
