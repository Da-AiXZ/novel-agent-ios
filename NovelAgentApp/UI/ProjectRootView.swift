import SwiftUI

struct ProjectRootView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var workspace: ProjectWorkspaceModel
    @State private var showingProviderSettings = false
    @State private var shareFile: ShareFile?

    init(projectID: UUID, appModel: AppModel) {
        _workspace = StateObject(
            wrappedValue: ProjectWorkspaceModel(projectID: projectID, appModel: appModel)
        )
    }

    var body: some View {
        TabView {
            WritingView(workspace: workspace)
                .tabItem {
                    Label("写作", systemImage: "sparkles")
                }

            ChaptersView(workspace: workspace, appModel: appModel)
                .tabItem {
                    Label("章节", systemImage: "doc.text")
                }

            StorySettingsView(workspace: workspace, appModel: appModel)
                .tabItem {
                    Label("设定", systemImage: "list.bullet.rectangle")
                }
        }
        .navigationTitle(workspace.snapshot?.project.title ?? "小说")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        workspace.export()
                    } label: {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showingProviderSettings = true
                    } label: {
                        Label("模型设置", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("项目菜单")
            }
        }
        .task { await workspace.load() }
        .onChange(of: workspace.exportURL) { url in
            if let url {
                shareFile = ShareFile(url: url)
                workspace.exportURL = nil
            }
        }
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
        }
        .sheet(isPresented: $showingProviderSettings) {
            NavigationStack {
                ProviderSettingsView()
                    .environmentObject(appModel)
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { workspace.errorMessage != nil },
                set: { if !$0 { workspace.errorMessage = nil } }
            )
        ) {
            Button("好") {}
        } message: {
            Text(workspace.errorMessage ?? "")
        }
    }
}

