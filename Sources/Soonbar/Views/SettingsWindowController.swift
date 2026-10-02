import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let windowID = NSUserInterfaceItemIdentifier("SoonbarSettings")
    private var window: NSWindow?

    func show(model: AppModel, prefs: PreferencesStore) {
        if window == nil {
            // Toolbar tabs, as in the system's settings windows; the window title follows the selected pane.
            let tabs = SettingsTabViewController()
            tabs.tabStyle = .toolbar
            for pane in SettingsPane.allCases {
                let content = pane.view
                    .environment(model)
                    .environment(prefs)
                    .frame(width: SettingsPane.size.width, height: SettingsPane.size.height)
                let hosting = NSHostingController(rootView: content)
                hosting.preferredContentSize = SettingsPane.size
                hosting.title = pane.title
                let item = NSTabViewItem(viewController: hosting)
                item.label = pane.title
                item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: pane.title)
                tabs.addTabViewItem(item)
            }
            let window = NSWindow(contentViewController: tabs)
            window.identifier = Self.windowID
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.title = SettingsPane.general.title
            window.setContentSize(SettingsPane.size)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Titles the window after the selected pane, as the system's settings windows do.
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let label = tabViewItem?.label { view.window?.title = label }
    }
}
