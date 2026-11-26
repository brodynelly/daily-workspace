import AppKit
import SwiftUI

/// Handles in-window shortcuts that SwiftUI's one-stroke menu shortcuts cannot express.
/// The monitor belongs to one hosting window; it never observes keys from other apps or windows.
@MainActor
struct MainWindowKeyboardMonitor: NSViewRepresentable {
    let handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyMonitorView { KeyMonitorView() }

    func updateNSView(_ view: KeyMonitorView, context: Context) { view.handle = handle }
}

@MainActor
final class KeyMonitorView: NSView {
    var handle: ((NSEvent) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, event.window === self.window, self.window?.isKeyWindow == true else {
                    return false
                }
                return self.handle?(event) == true
            }
            return handled ? nil : event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
