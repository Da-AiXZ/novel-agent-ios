import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(red: 0.02, green: 0.48, blue: 0.45)
    static let coral = Color(red: 0.88, green: 0.31, blue: 0.27)
    static let ink = Color(red: 0.10, green: 0.11, blue: 0.12)
    static let secondaryInk = Color(red: 0.36, green: 0.38, blue: 0.40)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let border = Color(uiColor: .separator).opacity(0.45)
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var isBusy = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)
        .disabled(disabled || isBusy)
        .accessibilityIdentifier("primaryAction")
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

