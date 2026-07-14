import SwiftUI
import UIKit
import NovelAgentCore

struct ChapterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let blueprint: ChapterBlueprint?
    let appModel: AppModel
    let onSaved: () -> Void

    @State private var chapter: Chapter
    @State private var title: String
    @State private var content: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        projectID: UUID,
        chapter: Chapter,
        blueprint: ChapterBlueprint?,
        appModel: AppModel,
        onSaved: @escaping () -> Void
    ) {
        self.projectID = projectID
        self.blueprint = blueprint
        self.appModel = appModel
        self.onSaved = onSaved
        _chapter = State(initialValue: chapter)
        _title = State(initialValue: chapter.title)
        _content = State(initialValue: chapter.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("章节标题", text: $title)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.surface)
                .accessibilityIdentifier("chapterTitle")

            UIKitTextEditor(text: $content)
                .accessibilityIdentifier("chapterEditor")
        }
        .navigationTitle("第 \(chapter.number) 章")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .disabled(isSaving || blueprint == nil || content.isEmpty)
                .accessibilityLabel("保存")
                .accessibilityIdentifier("saveChapter")
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
        guard let blueprint, !isSaving else {
            errorMessage = "缺少原章节蓝图，无法安全重建状态。"
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                chapter.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                chapter.content = content
                chapter.revision += 1
                chapter.updatedAt = Date()
                chapter.status = .needsReview
                try await appModel.reconcileEditedChapter(
                    projectID: projectID,
                    chapter: chapter,
                    blueprint: blueprint
                )
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct UIKitTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .systemBackground
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 24, right: 10)
        view.textContainer.lineFragmentPadding = 4
        view.text = text
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let selection = uiView.selectedRange
            uiView.text = text
            uiView.selectedRange = NSRange(
                location: min(selection.location, uiView.text.utf16.count),
                length: 0
            )
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}
