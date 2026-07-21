import Foundation
import SwiftUI

struct AgentPlanStep: Identifiable, Hashable, Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending, active, done, cancelled
    }

    var id: UUID = UUID()
    var title: String
    var status: Status = .pending
}

struct AgentPlan: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var title: String
    var steps: [AgentPlanStep]
    var updatedAt: Date = Date()

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        let done = steps.filter { $0.status == .done }.count
        return Double(done) / Double(steps.count)
    }

    var isComplete: Bool {
        !steps.isEmpty && steps.allSatisfy { $0.status == .done || $0.status == .cancelled }
    }

    /// Parse ```plan fenced blocks from assistant text.
    static func parse(from text: String) -> AgentPlan? {
        guard let fence = AgentContentParser.firstFence(in: text, languages: ["plan"]) else {
            return nil
        }
        var title = "Plan"
        var steps: [AgentPlanStep] = []
        for rawLine in fence.code.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("title:") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("- [x]") || line.hasPrefix("- [X]") || line.hasPrefix("* [x]") || line.hasPrefix("* [X]") {
                let t = line.drop(while: { $0 != "]" }).dropFirst().trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { steps.append(AgentPlanStep(title: t, status: .done)) }
                continue
            }
            if line.hasPrefix("- [ ]") || line.hasPrefix("* [ ]") {
                let t = line.drop(while: { $0 != "]" }).dropFirst().trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { steps.append(AgentPlanStep(title: t)) }
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let t = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { steps.append(AgentPlanStep(title: t)) }
            }
        }
        guard !steps.isEmpty else { return nil }
        return AgentPlan(title: title.isEmpty ? "Plan" : title, steps: steps)
    }
}

struct AgentPlanCard: View {
    @Environment(\.vibeTheme) private var themes
    let plan: AgentPlan
    var onToggle: (UUID) -> Void
    var onBuild: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        let t = themes.theme
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundStyle(t.vibeAccent)
                Text(plan.title)
                    .font(.headline)
                    .foregroundStyle(t.vibeForeground)
                Spacer()
                Text("\(Int(plan.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(t.vibeSecondary)
            }
            ProgressView(value: plan.progress)
                .tint(t.vibeAccent)
            ForEach(plan.steps) { step in
                Button {
                    onToggle(step.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.status == .done
                              ? "checkmark.circle.fill"
                              : (step.status == .active ? "circle.dotted" : "circle"))
                            .foregroundStyle(step.status == .done ? t.vibeSuccess : t.vibeMuted)
                        Text(step.title)
                            .font(.callout)
                            .foregroundStyle(t.vibeForeground)
                            .strikethrough(step.status == .done || step.status == .cancelled)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button("Build", action: onBuild)
                    .buttonStyle(.borderedProminent)
                    .tint(t.vibeAccent)
                    .disabled(plan.steps.allSatisfy { $0.status == .done })
                Button("Discard", role: .destructive, action: onDiscard)
                    .buttonStyle(.bordered)
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(t.vibeContentAlt)
        )
        .a11yCatalog("ghidra.vibe.agent.plan_card")
    }
}
