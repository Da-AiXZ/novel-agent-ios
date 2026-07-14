import SwiftUI
import NovelAgentCore

struct ChaptersView: View {
    @ObservedObject var workspace: ProjectWorkspaceModel
    let appModel: AppModel

    var body: some View {
        Group {
            if workspace.chapters.isEmpty {
                EmptyStateView(
                    systemImage: "doc.text",
                    title: "还没有章节",
                    message: "在写作页完成第一章后会显示在这里。"
                )
            } else {
                List(workspace.chapters) { chapter in
                    NavigationLink {
                        ChapterEditorView(
                            projectID: workspace.projectID,
                            chapter: chapter,
                            blueprint: workspace.snapshot?.blueprints.first {
                                $0.chapterNumber == chapter.number
                            },
                            appModel: appModel
                        ) {
                            Task { await workspace.load() }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(chapter.number)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(AppTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(2)
                                Text("\(characterCount(chapter.content)) 字 · v\(chapter.revision + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: chapter.status == .candidate ? "checkmark.seal.fill" : "exclamationmark.circle")
                                .foregroundStyle(
                                    chapter.status == .candidate ? AppTheme.accent : AppTheme.coral
                                )
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func characterCount(_ value: String) -> Int {
        value.filter { !$0.isWhitespace && !$0.isNewline }.count
    }
}

