import SwiftUI
import NovelAgentCore

struct WritingView: View {
    @ObservedObject var workspace: ProjectWorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    statusBand

                    if let blueprint = workspace.nextBlueprint {
                        BlueprintView(blueprint: blueprint)
                    }

                    if !workspace.streamingText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(
                                title: "当前正文",
                                trailing: "\(visibleCharacterCount) 字"
                            )
                            Text(workspace.streamingText)
                                .font(.body)
                                .foregroundStyle(AppTheme.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !workspace.findings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(
                                title: "审查结果",
                                trailing: "\(workspace.findings.count) 项"
                            )
                            ForEach(sortedFindings) { finding in
                                ReviewFindingRow(finding: finding)
                            }
                        }
                    }

                    if !workspace.chatMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "项目对话")
                            ForEach(workspace.chatMessages) { message in
                                ChatMessageView(message: message)
                            }
                        }
                    }
                }
                .padding(16)
            }

            VStack(spacing: 10) {
                if workspace.isWorking {
                    Button(role: .destructive) {
                        workspace.cancelOperation()
                    } label: {
                        Label("停止当前任务", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    PrimaryActionButton(
                        title: workspace.primaryActionTitle,
                        systemImage: workspace.nextBlueprint == nil ? "list.bullet.clipboard" : "wand.and.stars"
                    ) {
                        workspace.performPrimaryAction()
                    }
                }

                HStack(spacing: 8) {
                    TextField("询问角色、伏笔或下一步", text: $workspace.chatInput, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1 ... 4)
                        .accessibilityIdentifier("projectChatInput")
                    Button {
                        workspace.sendChat()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(
                        workspace.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityLabel("发送")
                }
            }
            .padding(12)
            .background(.bar)
        }
    }

    private var statusBand: some View {
        HStack(spacing: 12) {
            Image(systemName: workspace.isWorking ? "gearshape.2.fill" : "checkmark.circle")
                .foregroundStyle(workspace.isWorking ? AppTheme.coral : AppTheme.accent)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.isWorking ? "Agent 正在工作" : "准备就绪")
                    .font(.headline)
                Text(workspace.stageMessage.isEmpty ? "下一章：第 \(workspace.nextChapterNumber) 章" : workspace.stageMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            StatusBadge(
                text: workspace.snapshot?.project.targetPlatform.rawValue ?? "通用",
                color: AppTheme.accent
            )
        }
        .padding(.vertical, 4)
    }

    private var visibleCharacterCount: Int {
        workspace.streamingText.filter { !$0.isWhitespace && !$0.isNewline }.count
    }

    private var sortedFindings: [ReviewFinding] {
        workspace.findings.sorted {
            (FindingSeverity.allCases.firstIndex(of: $0.severity) ?? 99) <
                (FindingSeverity.allCases.firstIndex(of: $1.severity) ?? 99)
        }
    }
}

private struct BlueprintView: View {
    let blueprint: ChapterBlueprint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "第 \(blueprint.chapterNumber) 章蓝图",
                trailing: "\(blueprint.targetCharacterCount) 字"
            )
            Text(blueprint.provisionalTitle)
                .font(.title3.weight(.semibold))
            Text(blueprint.chapterGoal)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blueprint.beats.enumerated()), id: \.element.id) { index, beat in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(AppTheme.accent)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(beat.label)
                                .font(.subheadline.weight(.semibold))
                            Text(beat.event)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Label(blueprint.endingHook, systemImage: "arrow.turn.down.right")
                .font(.caption)
                .foregroundStyle(AppTheme.coral)
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ReviewFindingRow: View {
    let finding: ReviewFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusBadge(text: finding.severity.rawValue, color: severityColor)
                Text(finding.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(finding.reviewer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(finding.issue)
                .font(.subheadline.weight(.semibold))
            if !finding.evidence.isEmpty {
                Text(finding.evidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Text(finding.fix)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .padding(10)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var severityColor: Color {
        switch finding.severity {
        case .s1: .red
        case .s2: AppTheme.coral
        case .s3: .orange
        case .s4: AppTheme.accent
        }
    }
}

private struct ChatMessageView: View {
    let message: WorkspaceChatMessage

    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer(minLength: 42)
            }
            Text(message.content.isEmpty ? "…" : message.content)
                .font(.subheadline)
                .foregroundStyle(message.sender == .user ? Color.white : AppTheme.ink)
                .padding(10)
                .background(message.sender == .user ? AppTheme.accent : AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if message.sender == .agent {
                Spacer(minLength: 42)
            }
        }
    }
}
