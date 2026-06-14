import AppKit
import SwiftUI

/// System Settings-style preferences window: toolbar tabs hosting SwiftUI panes.
final class SettingsWindowController: NSWindowController {
    private let tabs: SettingsTabViewController

    private static let paneSize = NSSize(width: 780, height: 640)

    init(store: SettingsStore) {
        tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar

        func makeItem<V: View>(_ title: String, _ symbol: String, _ pane: V) -> NSTabViewItem {
            let size = Self.paneSize
            let root = pane
                .environmentObject(store)
                .frame(width: size.width, height: size.height)
            let host = NSHostingController(rootView: root)
            host.title = title
            host.preferredContentSize = size
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }

        tabs.addTabViewItem(makeItem("General", "gearshape", GeneralPane()))
        tabs.addTabViewItem(makeItem("Profiles", "terminal", ProfilesPane()))
        tabs.addTabViewItem(makeItem("Hotkey Window", "keyboard", HotkeyPane()))
        tabs.addTabViewItem(makeItem("Advanced", "wrench.and.screwdriver", AdvancedPane()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "General"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(Self.paneSize)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var hasShownOnce = false

    func show(tabIndex: Int?) {
        if let tabIndex, tabIndex >= 0, tabIndex < tabs.tabViewItems.count {
            tabs.selectedTabViewItemIndex = tabIndex
            window?.title = tabs.tabViewItems[tabIndex].label
        }
        if !hasShownOnce {
            window?.center()
            hasShownOnce = true
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? "Settings"
    }
}
