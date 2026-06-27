import SwiftUI

struct SettingsFormSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

typealias AdvancedSettingsSection<Content: View> = SettingsFormSection<Content>
typealias AboutSettingsSection<Content: View> = SettingsFormSection<Content>
typealias ClassifierSettingsSection<Content: View> = SettingsFormSection<Content>
typealias IntegrationsSettingsSection<Content: View> = SettingsFormSection<Content>
typealias RepositorySettingsSection<Content: View> = SettingsFormSection<Content>
