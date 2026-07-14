import SwiftUI
import NovelAgentCore

struct ProjectEntryView: View {
    @EnvironmentObject private var appModel: AppModel
    let projectID: UUID
    @State private var snapshot: StorySnapshot?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot {
                switch snapshot.project.phase {
                case .interviewing:
                    InterviewFlowView(snapshot: snapshot, onUpdated: setSnapshot)
                case .choosingDirection, .planning:
                    DirectionSelectionView(snapshot: snapshot, onUpdated: setSnapshot)
                case .writing, .reviewing:
                    ProjectRootView(projectID: projectID, appModel: appModel)
                }
            } else {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "无法打开项目",
                    message: errorMessage ?? "项目数据不可用。"
                )
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await appModel.snapshot(projectID: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setSnapshot(_ value: StorySnapshot) {
        snapshot = value
    }
}

