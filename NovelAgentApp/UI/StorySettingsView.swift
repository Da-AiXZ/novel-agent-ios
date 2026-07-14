import SwiftUI
import NovelAgentCore

struct StorySettingsView: View {
    @ObservedObject var workspace: ProjectWorkspaceModel
    let appModel: AppModel
    @State private var showingBriefEditor = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if let brief = workspace.snapshot?.brief {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "故事简报")
                            Button {
                                showingBriefEditor = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .accessibilityLabel("编辑故事简报")
                        }
                        LabeledValue(label: "题材", value: brief.genre)
                        LabeledValue(label: "核心梗", value: brief.coreHook)
                        LabeledValue(label: "主角", value: brief.protagonist)
                        LabeledValue(label: "欲望", value: brief.protagonistDesire)
                        LabeledValue(label: "矛盾", value: brief.coreConflict)
                        LabeledValue(label: "目标情绪", value: brief.targetEmotion)
                    }
                }

                if let snapshot = workspace.snapshot {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(
                                title: "大纲",
                                trailing: "\(snapshot.outline.count) 节点"
                            )
                            NavigationLink {
                                OutlineEditorView(
                                    projectID: workspace.projectID,
                                    nodes: snapshot.outline,
                                    appModel: appModel
                                ) {
                                    Task { await workspace.load() }
                                }
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .accessibilityLabel("编辑大纲")
                        }
                        ForEach(snapshot.outline.sorted { $0.position < $1.position }) { node in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(node.title)
                                    .font(
                                        node.kind == .book
                                            ? .headline
                                            : .subheadline.weight(.semibold)
                                    )
                                Text(node.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(
                            title: "角色与实体",
                            trailing: "\(snapshot.entities.count)"
                        )
                        ForEach(snapshot.entities) { entity in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: icon(for: entity.kind))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entity.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(entity.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(
                            title: "伏笔",
                            trailing: "\(snapshot.foreshadows.filter { $0.status != .resolved }.count) 未回收"
                        )
                        if snapshot.foreshadows.isEmpty {
                            Text("暂无伏笔")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.foreshadows) { item in
                                HStack(alignment: .top) {
                                    StatusBadge(
                                        text: item.status.rawValue,
                                        color: item.status == .resolved ? AppTheme.accent : AppTheme.coral
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(item.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "时间线", trailing: "\(snapshot.timeline.count)")
                        ForEach(snapshot.timeline.suffix(20)) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(event.order)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.label)
                                        .font(.subheadline.weight(.semibold))
                                    Text(event.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showingBriefEditor) {
            if let brief = workspace.snapshot?.brief {
                NavigationStack {
                    BriefEditorView(
                        projectID: workspace.projectID,
                        brief: brief,
                        appModel: appModel
                    ) {
                        Task { await workspace.load() }
                    }
                }
            }
        }
    }

    private func icon(for kind: EntityKind) -> String {
        switch kind {
        case .character: "person.fill"
        case .faction: "person.3.fill"
        case .location: "mappin.and.ellipse"
        case .item: "shippingbox.fill"
        case .worldRule: "ruler.fill"
        }
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value.isEmpty ? "未设置" : value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct BriefEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let appModel: AppModel
    let onSaved: () -> Void

    @State private var value: StoryBrief
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        projectID: UUID,
        brief: StoryBrief,
        appModel: AppModel,
        onSaved: @escaping () -> Void
    ) {
        self.projectID = projectID
        self.appModel = appModel
        self.onSaved = onSaved
        _value = State(initialValue: brief)
    }

    var body: some View {
        Form {
            Section("定位") {
                TextField("题材", text: $value.genre)
                Picker("平台", selection: $value.targetPlatform) {
                    ForEach(TargetPlatform.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                TextField("目标情绪", text: $value.targetEmotion)
                Stepper("计划 \(value.targetChapterCount) 章", value: $value.targetChapterCount, in: 20 ... 2_000, step: 10)
            }
            Section("故事核心") {
                TextField("核心梗", text: $value.coreHook, axis: .vertical)
                TextField("主角", text: $value.protagonist, axis: .vertical)
                TextField("主角欲望", text: $value.protagonistDesire, axis: .vertical)
                TextField("核心矛盾", text: $value.coreConflict, axis: .vertical)
            }
            Section("边界") {
                TextField("世界规则", text: $value.worldRules, axis: .vertical)
                TextField("创作禁区", text: $value.exclusions, axis: .vertical)
            }
        }
        .navigationTitle("故事简报")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(isSaving)
            }
        }
        .alert(
            "保存失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await appModel.updateBrief(projectID: projectID, brief: value)
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

