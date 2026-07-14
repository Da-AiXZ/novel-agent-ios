import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var showingImporter = false
    @State private var pendingRestoreURL: URL?
    @State private var confirmingRestore = false

    var body: some View {
        NavigationStack {
            Group {
                if appModel.projects.isEmpty && !appModel.isRefreshing {
                    EmptyStateView(
                        systemImage: "text.book.closed",
                        title: "还没有小说",
                        message: "创建一本书，从设定访谈开始。"
                    )
                } else {
                    List {
                        ForEach(appModel.projects) { project in
                            NavigationLink {
                                ProjectEntryView(projectID: project.id)
                            } label: {
                                ProjectRow(project: project)
                            }
                            .accessibilityIdentifier("project.\(project.id.uuidString)")
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { appModel.projects[$0].id }
                            Task {
                                for id in ids {
                                    try? await appModel.deleteProject(id: id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await appModel.refresh() }
                }
            }
            .navigationTitle("NovelAgent")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("恢复备份", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Label("模型设置", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多")

                    Button {
                        showingNewProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("创建小说")
                    .accessibilityIdentifier("createProject")
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectSheet()
                    .environmentObject(appModel)
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    ProviderSettingsView()
                        .environmentObject(appModel)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    pendingRestoreURL = urls.first
                    confirmingRestore = pendingRestoreURL != nil
                case let .failure(error):
                    appModel.presentedError = error.localizedDescription
                }
            }
            .confirmationDialog(
                "恢复将替换备份中同一项目的现有数据",
                isPresented: $confirmingRestore,
                titleVisibility: .visible
            ) {
                Button("恢复", role: .destructive) {
                    guard let url = pendingRestoreURL else { return }
                    Task {
                        let access = url.startAccessingSecurityScopedResource()
                        defer {
                            if access { url.stopAccessingSecurityScopedResource() }
                        }
                        do {
                            _ = try await appModel.restoreProject(from: url)
                        } catch {
                            appModel.presentedError = error.localizedDescription
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .alert(
                "错误",
                isPresented: Binding(
                    get: { appModel.presentedError != nil },
                    set: { if !$0 { appModel.presentedError = nil } }
                )
            ) {
                Button("好") { appModel.presentedError = nil }
            } message: {
                Text(appModel.presentedError ?? "")
            }
        }
    }
}

private struct ProjectRow: View {
    let project: StoryProject

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.phase == .writing ? "book.pages" : "text.bubble")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(project.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(phaseText)
                    Text(project.targetPlatform.rawValue)
                    Text(project.updatedAt, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private var phaseText: String {
        switch project.phase {
        case .interviewing: "设定访谈"
        case .choosingDirection: "选择方向"
        case .planning: "规划"
        case .writing: "写作中"
        case .reviewing: "待审查"
        }
    }
}

