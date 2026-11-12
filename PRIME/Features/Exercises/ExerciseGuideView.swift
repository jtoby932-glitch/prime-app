import SwiftData
import SwiftUI

enum GuideSection: String, CaseIterable, Identifiable {
    case overview, setup, perform, form, mistakes, safety, alternatives

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .setup: return "Equipment & Setup"
        case .perform: return "How to Perform"
        case .form: return "Proper Form"
        case .mistakes: return "Common Mistakes"
        case .safety: return "Safety"
        case .alternatives: return "Alternatives"
        }
    }
    var shortTitle: String {
        switch self {
        case .setup: return "Setup"
        case .perform: return "Perform"
        case .form: return "Form"
        case .mistakes: return "Mistakes"
        default: return title
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "text.alignleft"
        case .setup: return "wrench.adjustable"
        case .perform: return "list.number"
        case .form: return "figure.strengthtraining.functional"
        case .mistakes: return "exclamationmark.triangle"
        case .safety: return "cross.case"
        case .alternatives: return "arrow.triangle.branch"
        }
    }
}

extension Exercise {
    /// The bundled guide, or one assembled from a custom exercise's own notes.
    var guide: ExerciseGuide {
        if let bundled = ExerciseLibrary.shared.guide(for: slug) { return bundled }
        var guide = ExerciseGuide.empty
        guide.overview = isCustom ? "Your own exercise." : ""
        guide.steps = instructions
        guide.form = techniqueTips
        guide.mistakes = commonMistakes.map { ExerciseGuide.Mistake(what: $0, why: "", fix: "") }
        guide.tracking = equipment == .bodyweight ? .reps : .weightReps
        return guide
    }
}

/// The structured technique guide. Used on the exercise page and inside an active workout.
struct ExerciseGuideSections: View {
    let exercise: Exercise
    var sections: [GuideSection] = GuideSection.allCases
    var compact = false
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    var body: some View {
        let guide = exercise.guide
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections) { section in
                if has(section, guide) {
                    card(section) { content(section, guide) }
                        .id(section)
                }
            }
        }
    }

    private func has(_ section: GuideSection, _ guide: ExerciseGuide) -> Bool {
        switch section {
        case .overview: return !guide.overview.isEmpty || !compact
        case .setup: return !guide.setup.isEmpty
        case .perform: return !guide.steps.isEmpty
        case .form: return !guide.form.isEmpty || !guide.breathing.isEmpty
        case .mistakes: return !guide.mistakes.isEmpty
        case .safety: return !guide.safety.isEmpty
        case .alternatives: return !exercise.alternativeSlugs.isEmpty || !guide.easier.isEmpty || !guide.harder.isEmpty
        }
    }

    private func card<Content: View>(_ section: GuideSection, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(section.title, systemImage: section.symbol)
                .font(.primeTitle3)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .primeCard(padding: 16)
    }

    @ViewBuilder
    private func content(_ section: GuideSection, _ guide: ExerciseGuide) -> some View {
        switch section {
        case .overview:
            if !guide.overview.isEmpty {
                Text(guide.overview).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 12) {
                fact("Primary", exercise.primaryMuscleSummary)
                fact("Secondary", exercise.secondaryMuscles.isEmpty ? "–" : exercise.secondaryMuscles.map(\.displayName).joined(separator: ", "))
                fact("Equipment", exercise.equipment.displayName)
                fact("Type", exercise.mechanic.displayName + (guide.unilateral ? " · one side at a time" : ""))
                fact("Difficulty", exercise.difficulty.displayName)
                if !guide.pattern.isEmpty { fact("Movement", guide.pattern) }
                fact("Tracked as", trackingText(guide.tracking))
            }
        case .setup:
            numbered(guide.setup)
        case .perform:
            numbered(guide.steps)
        case .form:
            ForEach(guide.form, id: \.self) { cue in bullet(cue, symbol: "checkmark", tint: Theme.success) }
            if !guide.breathing.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wind").foregroundStyle(Theme.accentHighlight).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Breathing").font(.caption.weight(.bold)).foregroundStyle(Theme.accentHighlight)
                        Text(guide.breathing).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentSoft))
            }
        case .mistakes:
            ForEach(guide.mistakes, id: \.self) { mistake in MistakeCard(mistake: mistake) }
        case .safety:
            ForEach(guide.safety, id: \.self) { line in bullet(line, symbol: "shield.lefthalf.filled", tint: Theme.warning) }
            Text("Stop if you feel sharp or unusual pain. Comfortable technique varies with your build and the equipment.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        case .alternatives:
            let alternatives = exercise.alternativeSlugs.compactMap { slug in allExercises.first { $0.slug == slug } }
            if !guide.easier.isEmpty { variations("Easier options", guide.easier, symbol: "arrow.down.right") }
            if !guide.harder.isEmpty { variations("More challenging", guide.harder, symbol: "arrow.up.right") }
            if !alternatives.isEmpty {
                Text("Similar exercises").eyebrow()
                ForEach(alternatives) { option in
                    NavigationLink(value: Route.exercise(option.slug)) {
                        HStack {
                            ExerciseRow(exercise: option)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            if !guide.harder.isEmpty {
                Text("Harder isn't automatically better. Pick the version you can do with control.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func trackingText(_ tracking: TrackingType) -> String {
        switch tracking {
        case .weightReps: return "Weight × reps"
        case .reps: return "Reps (add weight if you like)"
        case .time: return "Time held"
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).eyebrow()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numbered(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.accentGradient))
                    Text(text).font(compact ? .subheadline : .body).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func bullet(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(tint).frame(width: 20).padding(.top, 3)
            Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func variations(_ title: String, _ items: [String], symbol: String) -> some View {
        Text(title).eyebrow()
        ForEach(items, id: \.self) { item in
            if let match = allExercises.first(where: { $0.slug == item }) {
                NavigationLink(value: Route.exercise(match.slug)) {
                    Label(match.name, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentHighlight)
                }
            } else {
                Label(item, systemImage: symbol).font(.subheadline).foregroundStyle(Theme.textPrimary)
            }
        }
    }
}

struct MistakeCard: View {
    let mistake: ExerciseGuide.Mistake

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(mistake.what, systemImage: "xmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.textPrimary, Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
            if !mistake.why.isEmpty {
                Text(mistake.why).font(.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if !mistake.fix.isEmpty {
                Label(mistake.fix, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Quick technique check from inside a workout. A sheet, so the workout underneath is untouched.
struct ExerciseGuideSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bodyModel) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ExerciseIllustration(exercise: exercise, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).font(.primeTitle3).foregroundStyle(Theme.textPrimary)
                            Text("Your workout keeps running while you read.").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    ExerciseGuideSections(exercise: exercise, sections: [.setup, .perform, .form, .mistakes, .safety], compact: true)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .primeBackground()
            .navigationTitle("Technique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
    }
}
