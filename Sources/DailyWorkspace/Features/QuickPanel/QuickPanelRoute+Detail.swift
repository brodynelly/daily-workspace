extension QuickPanelRoute {
    var detail: String {
        switch self {
        case .home: "Choose a quick-access view or open the full workspace."
        case .agents: "Open the Assistant in Daily Workspace to inspect agent activity."
        case .sessions: "Open the Assistant in Daily Workspace to inspect running sessions."
        case .files: "Open Notes in Daily Workspace to browse and search files."
        case .projects: "Open Projects in Daily Workspace for project context and native status."
        case .workspaces: "Open Projects in Daily Workspace to browse connected workspaces."
        case .ssh: "Browse workspace connections or open the Assistant in Daily Workspace."
        case .tmux: "Browse sessions or open the Assistant in Daily Workspace."
        case .shortcuts: "Choose a view here; the full workspace has its own commands and shortcuts."
        case .attention: "Open Loops in Daily Workspace shows source-owned items and their native status."
        case .system: "Open the workspace or use macOS System Settings."
        case .music: "Return to Home or open another view from the navigation list."
        case .monitor: "CPU, memory, network and processes, read live while this view is open."
        case .calendar: "Today's agenda and next event from Apple Calendar."
        }
    }
}
