import SwiftUI
import NovelAgentCore
import NovelAgentProviders

struct ProviderSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var profileID = UUID()
    @State private var name = "默认模型"
    @State private var kind = ProviderKind.openAIResponses
    @State private var baseURL = ProviderConfiguration.defaultBaseURL(
        for: .openAIResponses
    ).absoluteString
    @State private var strongModel = "gpt-5.6"
    @State private var fastModel = "gpt-5.4-mini"
    @State private var embeddingModel = "text-embedding-3-small"
    @State private var preset = QualityPreset.quality
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("供应商") {
                Picker("协议", selection: $kind) {
                    ForEach(ProviderKind.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                TextField("配置名称", text: $name)
                TextField("HTTPS Base URL", text: $baseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("模型路由") {
                Picker("模式", selection: $preset) {
                    ForEach(QualityPreset.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                TextField("强模型", text: $strongModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("快速模型", text: $fastModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if kind != .anthropicMessages {
                    TextField("Embedding 模型（可空）", text: $embeddingModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section("密钥") {
                SecureField(
                    appModel.activeProfile == nil ? "API Key" : "留空则保留现有密钥",
                    text: $apiKey
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
            }

            Section {
                Button {
                    test()
                } label: {
                    HStack {
                        Label("测试连接", systemImage: "network")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting || isSaving || !configurationIsValid)

                Button {
                    save()
                } label: {
                    HStack {
                        Label("保存并启用", systemImage: "checkmark.circle")
                        Spacer()
                        if isSaving { ProgressView() }
                    }
                }
                .disabled(isSaving || isTesting || !configurationIsValid)
                .accessibilityIdentifier("saveProvider")
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .navigationTitle("模型设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .onAppear(perform: loadExisting)
        .onChange(of: kind) { newValue in
            applyDefaults(for: newValue)
        }
        .alert(
            "配置失败",
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

    private var configurationIsValid: Bool {
        guard let url = URL(string: baseURL), url.scheme == "https", url.host != nil else {
            return false
        }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !strongModel.trimmingCharacters(in: .whitespaces).isEmpty &&
            !fastModel.trimmingCharacters(in: .whitespaces).isEmpty &&
            (appModel.activeProfile != nil || !apiKey.isEmpty)
    }

    private func configuration() throws -> ProviderConfiguration {
        guard let url = URL(string: baseURL) else {
            throw ProviderError.invalidConfiguration("Base URL 无效")
        }
        return ProviderConfiguration(
            id: profileID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            baseURL: url,
            strongModel: strongModel.trimmingCharacters(in: .whitespacesAndNewlines),
            fastModel: fastModel.trimmingCharacters(in: .whitespacesAndNewlines),
            embeddingModel: embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines),
            qualityPreset: preset
        )
    }

    private func loadExisting() {
        guard let profile = appModel.activeProfile else { return }
        let configuration = profile.configuration
        profileID = configuration.id
        name = configuration.name
        kind = configuration.kind
        baseURL = configuration.baseURL.absoluteString
        strongModel = configuration.strongModel
        fastModel = configuration.fastModel
        embeddingModel = configuration.embeddingModel ?? ""
        preset = configuration.qualityPreset
    }

    private func applyDefaults(for kind: ProviderKind) {
        baseURL = ProviderConfiguration.defaultBaseURL(for: kind).absoluteString
        switch kind {
        case .openAIResponses:
            strongModel = "gpt-5.6"
            fastModel = "gpt-5.4-mini"
            embeddingModel = "text-embedding-3-small"
        case .anthropicMessages:
            strongModel = "claude-opus-4-6"
            fastModel = "claude-haiku-4-5"
            embeddingModel = ""
        case .openAICompatible:
            strongModel = "deepseek-chat"
            fastModel = "deepseek-chat"
            embeddingModel = ""
        }
    }

    private func test() {
        isTesting = true
        statusMessage = nil
        Task {
            defer { isTesting = false }
            do {
                let key: String
                if apiKey.isEmpty,
                   let profile = appModel.activeProfile,
                   let saved = try appModel.keychain.value(for: profile.keyReference) {
                    key = saved
                } else {
                    key = apiKey
                }
                let result = try await appModel.testProvider(
                    configuration: configuration(),
                    apiKey: key
                )
                statusMessage = "连接成功 · \(result.latencyMilliseconds) ms"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try appModel.saveProfile(
                    configuration: configuration(),
                    apiKey: apiKey
                )
                statusMessage = "已启用"
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

