import SwiftUI

struct NewProjectSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("小说名称") {
                    TextField("可以先用临时名称", text: $title)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("newProjectTitle")
                }
            }
            .navigationTitle("创建小说")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        isCreating = true
                        Task {
                            defer { isCreating = false }
                            do {
                                _ = try await appModel.createProject(title: title)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(isCreating)
                    .accessibilityIdentifier("confirmCreateProject")
                }
            }
            .alert(
                "创建失败",
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
    }
}

