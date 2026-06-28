import SwiftUI

struct SettingsPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct SettingsPageLoadingContent<Actions: View>: View {
    let title: String
    private let actions: Actions

    init(
        title: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.headline)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension SettingsPageLoadingContent where Actions == EmptyView {
    init(title: String) {
        self.title = title
        actions = EmptyView()
    }
}

struct SettingsHeaderProgressIndicator: View {
    let label: String

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .accessibilityLabel(label)
    }
}

struct SettingsInlineProgressStatus: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsPageScrollContent<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
    }
}

struct SettingsPageErrorContent<Actions: View>: View {
    let title: String
    let message: String
    let recovery: String
    private let actions: Actions

    init(
        title: String,
        message: String,
        recovery: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.recovery = recovery
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
            Text(recovery)
        } actions: {
            actions
        }
    }
}

struct SettingsStatusBanner<Details: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    private let details: Details

    init(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder details: () -> Details
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.details = details()
    }

    var body: some View {
        TintedStatusBanner(tint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(tint)
                details
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension SettingsStatusBanner where Details == EmptyView {
    init(title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        details = EmptyView()
    }
}

struct SettingsProgressBanner: View {
    let title: String

    var body: some View {
        TintedStatusBanner(tint: .blue) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
