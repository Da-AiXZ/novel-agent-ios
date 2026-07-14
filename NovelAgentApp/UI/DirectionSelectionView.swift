import SwiftUI
import NovelAgentCore

struct DirectionSelectionView: View {
    @EnvironmentObject private var appModel: AppModel
    let snapshot: StorySnapshot
    let onUpdated: (StorySnapshot) -> Void

    @State private var selectedID: UUID?
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("选择整本方向")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("确认后会建立全书阶段、基础角色和前三章蓝图。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(snapshot.candidateDirections) { direction in
                    Button {
                        selectedID = direction.id
                    } label: {
                        DirectionCard(
                            direction: direction,
                            selected: selectedID == direction.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle(snapshot.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                PrimaryActionButton(
                    title: "确认方向并建立计划",
                    systemImage: "checkmark",
                    isBusy: isBusy,
                    disabled: selectedDirection == nil
                ) {
                    confirm()
                }
                Button {
                    regenerate()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
                .disabled(isBusy)
            }
            .padding(16)
            .background(.bar)
        }
        .alert(
            "操作失败",
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

    private var selectedDirection: StoryDirection? {
        snapshot.candidateDirections.first { $0.id == selectedID }
    }

    private func confirm() {
        guard let direction = selectedDirection, !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                onUpdated(
                    try await appModel.confirmDirection(
                        projectID: snapshot.project.id,
                        direction: direction
                    )
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func regenerate() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                onUpdated(
                    try await appModel.regenerateDirections(projectID: snapshot.project.id)
                )
                selectedID = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct DirectionCard: View {
    let direction: StoryDirection
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(direction.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AppTheme.accent : .secondary)
            }
            Text(direction.logline)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
            Text(direction.positioning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(direction.sellingPoints.prefix(3), id: \.self) {
                    Label($0, systemImage: "sparkle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? AppTheme.accent : AppTheme.border, lineWidth: selected ? 2 : 1)
        )
    }
}

