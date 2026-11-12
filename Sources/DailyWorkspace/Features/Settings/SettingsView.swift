import SwiftUI

/// Settings window: Vault, Editor, AI, Luuna, Permissions, each tab on the Luuna surface.
struct SettingsView: View {
    var body: some View {
        TabView {
            VaultSettingsView().tabItem { Label("Vault", systemImage: "folder") }
            EditorSettingsView().tabItem { Label("Editor", systemImage: "cursorarrow.motionlines") }
            AISettingsView().tabItem { Label("AI", systemImage: "bubble.left") }
            LuunaSettingsView().tabItem { Label("Luuna", systemImage: "point.3.connected.trianglepath.dotted") }
            PermissionsSettingsView().tabItem { Label("Permissions", systemImage: "hand.raised") }
        }
        .frame(width: 640, height: 560)
        .background(Theme.surface)
        .tint(Theme.accent)
    }
}

/// One Settings tab: a scrolling column of titled groups, 24 pt from the window edge, on the surface.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s8) { content }
                .padding(Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface)
        .foregroundStyle(Theme.inkBody)
    }
}

/// A titled group of settings rows (Luuna Settings): the section title, an optional description, then the
/// rows separated by hairlines.
struct SettingsGroup<Content: View>: View {
    let title: String
    var description: String?
    @ViewBuilder var content: Content

    init(_ title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title, description: description).padding(.bottom, Space.s1)
            content
        }
        .accessibilityElement(children: .contain)
    }
}

/// A setting whose value is a path or another identity: the title, then the value whole in monospace (it
/// wraps, never truncates, and can be selected), with optional actions trailing.
struct PathSettingsRow<Actions: View>: View {
    let title: String
    let path: String
    var monospaced = true
    var divider = true
    @ViewBuilder var actions: Actions

    init(
        _ title: String, path: String, monospaced: Bool = true, divider: Bool = true,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.path = path
        self.monospaced = monospaced
        self.divider = divider
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.s6) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).textRole(.bodyStrong, lineBox: false).foregroundStyle(Theme.ink)
                Text(verbatim: path)
                    .font(monospaced ? TextRole.mono.font : TextRole.body.font)
                    .foregroundStyle(monospaced ? Theme.inkBody : Theme.inkMuted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s2) { actions }.fixedSize()
        }
        .padding(.vertical, Space.s4)
        .overlay(alignment: .bottom) { if divider { Hairline() } }
        .accessibilityElement(children: .contain)
    }
}

extension PathSettingsRow where Actions == EmptyView {
    init(_ title: String, path: String, monospaced: Bool = true, divider: Bool = true) {
        self.init(title, path: path, monospaced: monospaced, divider: divider) { EmptyView() }
    }
}

/// A muted note under a settings group.
struct SettingsNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .textRole(.bodySmall, lineBox: false)
            .foregroundStyle(Theme.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.s3)
    }
}
