import SwiftUI
import NovelAgentCore

struct OutlineEditorView: View {
    let projectID: UUID
    let appModel: AppModel
    let onSaved: () -> Void

    @State private var nodes: [OutlineNode]
    @State private var editingNode: OutlineNode?
    @State private var confirmingSave = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        projectID: UUID,
        nodes: [OutlineNode],
        appModel: AppModel,
        onSaved: @escaping () -> Void
    ) {
        self.projectID = projectID
        self.appModel = appModel
        self.onSaved = onSaved
        _nodes = State(initialValue: nodes)
    }

    var body: some View {
        List {
            ForEach(nodes.sorted { $0.position < $1.position }) { node in
                Button {
                    editingNode = node
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(node.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("编辑大纲")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    confirmingSave = true
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .disabled(isSaving)
                .accessibilityLabel("保存大纲")
            }
        }
        .sheet(item: $editingNode) { node in
            OutlineNodeEditor(node: node) { updated in
                guard let index = nodes.firstIndex(where: { $0.id == updated.id }) else { return }
                nodes[index] = updated
            }
        }
        .confirmationDialog(
            "保存后，尚未写作的章节蓝图需要重新生成",
            isPresented: $confirmingSave,
            titleVisibility: .visible
        ) {
            Button("保存并重新规划", role: .destructive) { save() }
            Button("取消", role: .cancel) {}
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
                _ = try await appModel.replaceOutline(projectID: projectID, outline: nodes)
                onSaved()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct OutlineNodeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var node: OutlineNode
    let onSave: (OutlineNode) -> Void

    init(node: OutlineNode, onSave: @escaping (OutlineNode) -> Void) {
        _node = State(initialValue: node)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $node.title)
                TextField("内容", text: $node.summary, axis: .vertical)
                    .lineLimit(5 ... 14)
            }
            .navigationTitle("大纲节点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(node)
                        dismiss()
                    }
                }
            }
        }
    }
}

