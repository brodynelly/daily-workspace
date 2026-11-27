import Foundation

/// Values compatible with the QAP configuration schema. The panel's integrations can read this
/// independently of CLI requests; the CLI never transmits paths or arbitrary configuration over IPC.
struct QuickPanelControlConfiguration: Decodable {
    var dotfiles: String
    var attentionFile: String
    var clipboardFeedback: Bool
    var terminalBorder: Bool
    var zenMouse: Bool
    var font: String
    var glass: Bool
    var musicFixture: String?

    enum CodingKeys: String, CodingKey {
        case dotfiles, font, glass
        case attentionFile = "attention_file"
        case clipboardFeedback = "clipboard_feedback"
        case terminalBorder = "terminal_border"
        case zenMouse = "zen_mouse"
        case musicFixture = "music_fixture"
    }

    init() {
        dotfiles =
            ProcessInfo.processInfo.environment["DOTFILES_DIR"]
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("github/dotfiles-mac").path
        attentionFile = "/tmp/sketchybar-opencode-agents.json"
        clipboardFeedback = true
        terminalBorder = true
        zenMouse = false
        font = "JetBrains Mono"
        glass = true
        musicFixture = nil
    }

    func shouldCenterMouse(applicationName: String?, accessibilityTrusted: Bool) -> Bool {
        zenMouse && accessibilityTrusted && applicationName == "Zen Browser"
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        dotfiles = try values.decodeIfPresent(String.self, forKey: .dotfiles) ?? dotfiles
        attentionFile = try values.decodeIfPresent(String.self, forKey: .attentionFile) ?? attentionFile
        clipboardFeedback = try values.decodeIfPresent(Bool.self, forKey: .clipboardFeedback) ?? clipboardFeedback
        terminalBorder = try values.decodeIfPresent(Bool.self, forKey: .terminalBorder) ?? terminalBorder
        zenMouse = try values.decodeIfPresent(Bool.self, forKey: .zenMouse) ?? zenMouse
        font = try values.decodeIfPresent(String.self, forKey: .font) ?? font
        glass = try values.decodeIfPresent(Bool.self, forKey: .glass) ?? glass
        musicFixture = try values.decodeIfPresent(String.self, forKey: .musicFixture)
    }

    static func load(at url: URL? = nil) throws -> Self {
        let file =
            url
            ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/daily-workspace/quick-panel.json")
        do { return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file)) } catch let error as CocoaError
            where error.code == .fileReadNoSuchFile && url == nil
        { return Self() }
    }
}
