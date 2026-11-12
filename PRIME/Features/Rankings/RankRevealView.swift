import SwiftUI

/// Multi-stage reveal for a performance whose rank has already been calculated and saved.
/// Analysis shows the real numbers behind the result, then the emblem is revealed, then the breakdown.
struct RankRevealView: View {
    enum Stage: Int, Comparable {
        case analysis, reveal, breakdown
        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let reveal: RankReveal
    var initialStage: Stage = .analysis
    /// Debug screenshots pin a stage instead of advancing.
    var frozen = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.motion) private var motion
    @State private var stage: Stage = .analysis
    @State private var completedSteps = 0
    @State private var emblemIn = false
    @State private var burst = false
    @State private var revealStart = Date()
    @State private var sequence: Task<Void, Never>?

    private var tier: RankTier { reveal.tier }
    private var unit: WeightUnit { reveal.unit }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                switch stage {
                case .analysis: analysis.transition(.opacity)
                case .reveal, .breakdown: revealed.transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .contentShape(Rectangle())
        .onTapGesture { skipAhead() }
        .onAppear(perform: begin)
        .onDisappear { sequence?.cancel() }
        .statusBarHidden(stage < .breakdown)
        .accessibilityAction(named: "Skip animation") { skipAhead() }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            Color(hex: 0x020306).ignoresSafeArea()
            RadialGradient(colors: [Color(hex: 0x0C1A36), .clear], center: .center, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .opacity(stage == .analysis ? 1 : 0.5)
            if stage >= .reveal {
                RadialGradient(colors: [tier.glow.opacity(0.55 + 0.25 * tier.prestige), tier.glow.opacity(0.08), .clear],
                               center: UnitPoint(x: 0.5, y: 0.32), startRadius: 10, endRadius: burst ? 420 : 40)
                    .ignoresSafeArea()
                    .opacity(burst ? 1 : 0)
                if tier >= .silver && motion.allowsMovement {
                    GeometryReader { proxy in
                        RevealRays(color: tier.glow, count: tier >= .diamond ? 18 : 12)
                            .frame(width: 520, height: 520)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.32)
                    }
                    .ignoresSafeArea()
                    .opacity(burst ? 0.35 + 0.25 * tier.prestige : 0)
                    .allowsHitTesting(false)
                }
                if tier >= .gold && motion.allowsMovement {
                    RevealParticles(color: tier.glow, start: revealStart, density: tier >= .elite ? 80 : (tier >= .platinum ? 50 : 30))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                if motion.allowsMovement {
                    // Shockwave: a ring that leaves the emblem as it lands.
                    GeometryReader { proxy in
                        Circle()
                            .stroke(tier.glow.opacity(burst ? 0 : 0.8), lineWidth: burst ? 1 : 6)
                            .frame(width: burst ? 620 : 120, height: burst ? 620 : 120)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.32)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Stage 2 — analysis

    private var steps: [(title: String, value: String)] {
        let set = reveal.result.set
        var lines: [(title: String, value: String)] = []
        switch reveal.result.method {
        case .relativeLoad:
            lines.append(("Analysing performance", "\(Format.weight(set.weightKg, unit: unit)) × \(set.reps)"))
            lines.append(("Calculating strength", "\(set.isTestedMax ? "Tested" : "Estimated") 1RM \(Format.estimate(reveal.result.estimatedOneRepMaxKg ?? 0, unit: unit))"))
            lines.append(("Evaluating your rank", "\(Format.ratio(reveal.result.metric)) on PRIME's \(reveal.exerciseName) ladder"))
        default:
            lines.append(("Analysing performance", set.weightKg > 0 ? "\(set.reps) reps +\(Format.weight(set.weightKg, unit: unit))" : "\(set.reps) reps"))
            lines.append(("Calculating strength", "\(Format.number(reveal.result.metric, maxFractionDigits: 1)) bodyweight reps"))
            lines.append(("Evaluating your rank", "on PRIME's \(reveal.exerciseName) ladder"))
        }
        return lines
    }

    private var analysis: some View {
        VStack(spacing: 36) {
            Spacer()
            AnalysisRings(active: motion.allowsMovement)
                .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().strokeBorder(Theme.borderStrong, lineWidth: 1.5).frame(width: 22, height: 22)
                            if index < completedSteps {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accentHighlight)
                                    .transition(.scale.combined(with: .opacity))
                            } else if index == completedSteps {
                                ProgressView().controlSize(.mini).tint(Theme.accentHighlight)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title.uppercased())
                                .font(.caption.weight(.bold)).tracking(2)
                                .foregroundStyle(index <= completedSteps ? Theme.textPrimary : Theme.textTertiary)
                            if index < completedSteps {
                                Text(step.value).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.accentHighlight)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .opacity(index <= completedSteps ? 1 : 0.35)
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
            Spacer()
            Text("Tap to skip").font(.caption).foregroundStyle(Theme.textTertiary).padding(.bottom, 12)
        }
    }

    // MARK: Stage 3–5 — reveal and breakdown

    private var revealed: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 40)
                Text(reveal.exerciseName.uppercased())
                    .font(.caption.weight(.bold)).tracking(2.5)
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(emblemIn ? 1 : 0)
                RankEmblem(tier: tier, size: 190, animated: true, aura: true)
                    .scaleEffect(emblemIn ? 1 : (motion.allowsMovement ? 0.2 : 0.9))
                    .blur(radius: emblemIn || !motion.allowsMovement ? 0 : 14)
                    .opacity(emblemIn ? 1 : 0)
                    .rotation3DEffect(.degrees(emblemIn || !motion.allowsMovement ? 0 : 70), axis: (x: 0, y: 1, z: 0))
                    .modifier(FloatModifier(active: emblemIn && stage == .reveal))
                VStack(spacing: 6) {
                    Text(tier.name.uppercased())
                        .font(.system(size: 40, weight: .heavy).width(.expanded))
                        .tracking(emblemIn ? 4 : 18)
                        .foregroundStyle(tier == .unranked ? AnyShapeStyle(Theme.textSecondary) : AnyShapeStyle(tier.gradient))
                        .shimmer(repeats: tier >= .elite, color: .white)
                        .shadow(color: tier.glow.opacity(0.5), radius: 16)
                        .opacity(emblemIn ? 1 : 0)
                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .opacity(emblemIn ? 1 : 0)
                }
                if stage == .breakdown {
                    breakdown
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(stage != .breakdown)
    }

    private var headline: String {
        if let previous = reveal.previousTier {
            if tier > previous { return "Up from \(previous.name)" }
            if tier == previous { return "Holding \(tier.name)" }
            return "Your best on this lift is \(previous.name)"
        }
        return tier == .unranked ? "Every lift starts somewhere" : "Your first rank on this lift"
    }

    private var breakdown: some View {
        let result = reveal.result
        let set = result.set
        return VStack(spacing: 14) {
            VStack(spacing: 10) {
                HStack {
                    Text(tier.name).font(.caption.weight(.bold)).foregroundStyle(tier.color)
                    Spacer()
                    if let next = tier.next {
                        Text("\(Format.percent(result.placement.progress))").font(.primeNumber(20)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(next.name).font(.caption.weight(.bold)).foregroundStyle(next.color)
                    } else {
                        Text("Top of the ladder").font(.caption.weight(.bold)).foregroundStyle(tier.color)
                    }
                }
                ProgressBar(progress: tier.next == nil ? 1 : result.placement.progress, tint: AnyShapeStyle(tier.gradient), height: 10)
                if let target = RankFormat.targetText(reveal.next, unit: unit) {
                    Text(target).font(.caption).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .primeCard(padding: 16, highlight: tier.color)

            VStack(spacing: 10) {
                MetricRow(label: "Exercise", value: reveal.exerciseName)
                if result.method == .relativeLoad {
                    MetricRow(label: "Lift", value: "\(Format.weight(set.weightKg, unit: unit)) × \(set.reps)")
                    MetricRow(label: set.isTestedMax ? "Tested 1RM" : "Estimated 1RM (Epley)", value: Format.estimate(result.estimatedOneRepMaxKg ?? 0, unit: unit))
                    if let bodyweight = set.bodyweightKg { MetricRow(label: "Bodyweight", value: Format.weight(bodyweight, unit: unit)) }
                    MetricRow(label: "Relative strength", value: Format.ratio(result.metric))
                } else {
                    MetricRow(label: "Set", value: set.weightKg > 0 ? "\(set.reps) reps +\(Format.weight(set.weightKg, unit: unit))" : "\(set.reps) reps")
                    MetricRow(label: "Bodyweight reps", value: Format.number(result.metric, maxFractionDigits: 1))
                }
                MetricRow(label: "Previous rank", value: reveal.previousTier?.name ?? "None", valueColor: reveal.previousTier?.color ?? Theme.textSecondary)
                MetricRow(label: "Personal best", value: reveal.isPersonalBest ? "Yes, new best" : "No", valueColor: reveal.isPersonalBest ? Theme.success : Theme.textSecondary)
            }
            .primeCard(padding: 16)

            Text("\(RankingStandard.sourceLabel). Estimated maxes are estimates.")
                .font(.caption).foregroundStyle(Theme.textTertiary)

            Button("Done") { dismiss() }.buttonStyle(.primePrimary)
            Button("View \(reveal.exerciseName) ranking") {
                dismiss()
                let slug = reveal.exerciseSlug
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    appState.selectedTab = .rankings
                    appState.debugRoute = nil
                    appState.pendingRoute = .exerciseRank(slug)
                }
            }
            .buttonStyle(.primeSecondary)
        }
    }

    // MARK: Sequencing

    private func begin() {
        stage = initialStage
        completedSteps = initialStage == .analysis ? 0 : steps.count
        if initialStage >= .reveal { showEmblem(animated: false) }
        if frozen {
            if initialStage == .analysis { completedSteps = 2 }
            return
        }
        guard initialStage == .analysis else { return }
        if !motion.allowsAnimation {
            completedSteps = steps.count
            stage = .breakdown
            showEmblem(animated: false)
            return
        }
        let step: UInt64 = motion.allowsMovement ? 620_000_000 : 220_000_000
        sequence = Task { @MainActor in
            for index in 1...steps.count {
                try? await Task.sleep(nanoseconds: step)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { completedSteps = index }
                Haptics.tap()
            }
            try? await Task.sleep(nanoseconds: step / 2)
            guard !Task.isCancelled else { return }
            enterReveal()
            try? await Task.sleep(nanoseconds: motion.allowsMovement ? 1_500_000_000 : 400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(motion.animation(.spring(response: 0.55, dampingFraction: 0.88))) { stage = .breakdown }
        }
    }

    private func enterReveal() {
        withAnimation(.easeInOut(duration: 0.3)) { stage = .reveal }
        showEmblem(animated: true)
        Haptics.rankReveal(tier)
    }

    private func showEmblem(animated: Bool) {
        revealStart = Date()
        if animated {
            withAnimation(motion.animation(.spring(response: 0.7, dampingFraction: 0.55))) { emblemIn = true }
            withAnimation(motion.animation(.easeOut(duration: 1.3).delay(0.12))) { burst = true }
        } else {
            emblemIn = true
            burst = true
        }
    }

    /// Never trap the user in an animation: a tap moves straight to the next stage.
    private func skipAhead() {
        guard !frozen else { return }
        switch stage {
        case .analysis:
            sequence?.cancel()
            completedSteps = steps.count
            enterReveal()
            sequence = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(motion.animation()) { stage = .breakdown }
            }
        case .reveal:
            sequence?.cancel()
            withAnimation(motion.animation()) { stage = .breakdown }
        case .breakdown:
            break
        }
    }
}

/// A slow hover, so the emblem feels held in the air rather than pinned.
struct FloatModifier: ViewModifier {
    let active: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: active && up ? -7 : 0)
            .onChange(of: active) { _, value in
                guard value else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(0.8)) { up = true }
            }
    }
}

/// Two counter-rotating arcs and a pulse. Restrained "working" visual.
struct AnalysisRings: View {
    let active: Bool
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.border, lineWidth: 1)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
            Circle()
                .trim(from: 0, to: 0.18)
                .stroke(Theme.accentHighlight.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .padding(18)
                .rotationEffect(.degrees(spin ? -360 : 0))
            Circle()
                .fill(Theme.accent.opacity(0.25))
                .padding(46)
                .scaleEffect(pulse ? 1.15 : 0.85)
                .blur(radius: 8)
            PrimeMark().fill(Theme.accentGradient).frame(width: 34, height: 34)
        }
        .onAppear {
            guard active else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// Soft light rays behind higher tiers, slowly turning.
struct RevealRays: View {
    let color: Color
    let count: Int
    @State private var turn = false

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for index in 0..<count {
                let angle = Double(index) / Double(count) * 2 * .pi
                var ray = Path()
                ray.move(to: center)
                ray.addLine(to: CGPoint(x: center.x + radius * cos(angle - 0.06), y: center.y + radius * sin(angle - 0.06)))
                ray.addLine(to: CGPoint(x: center.x + radius * cos(angle + 0.06), y: center.y + radius * sin(angle + 0.06)))
                ray.closeSubpath()
                context.fill(ray, with: .radialGradient(Gradient(colors: [color.opacity(0.5), .clear]), center: center, startRadius: 20, endRadius: radius))
            }
        }
        .rotationEffect(.degrees(turn ? 30 : 0))
        .onAppear { withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { turn = true } }
    }
}

/// A short burst of drifting sparks for Platinum and above. Stops drawing after a few seconds.
struct RevealParticles: View {
    let color: Color
    let start: Date
    let density: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard elapsed < 4.5 else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.32)
                for index in 0..<density {
                    let seed = Double(index) * 12.9898
                    let angle = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1) * 2 * .pi
                    let speed = 70 + abs((cos(seed * 1.7) * 9871.13).truncatingRemainder(dividingBy: 1)) * 170
                    let delay = abs((sin(seed * 3.1) * 1234.5).truncatingRemainder(dividingBy: 1)) * 0.4
                    let t = max(0, elapsed - delay)
                    let distance = speed * t * (1 - min(1, t / 4) * 0.4)
                    let point = CGPoint(x: origin.x + cos(angle) * distance, y: origin.y + sin(angle) * distance + 18 * t * t)
                    let life = max(0, 1 - t / 3.2)
                    let radius = 1.2 + 2.2 * life
                    context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(color.opacity(0.85 * life)))
                }
            }
        }
    }
}
