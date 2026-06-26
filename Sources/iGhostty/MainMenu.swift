import AppKit

enum MenuID {
    static let profilesMenu = NSUserInterfaceItemIdentifier("iGhostty.profilesMenu")
    static let newTabProfileMenu = NSUserInterfaceItemIdentifier("iGhostty.newTabProfileMenu")
}

enum MainMenuBuilder {
    static func build(delegate: AppDelegate) -> NSMenu {
        let main = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About iGhostty", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Secure Keyboard Entry", action: #selector(AppDelegate.toggleSecureKeyboardEntry(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide iGhostty", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit iGhostty", action: #selector(AppDelegate.quitRequested(_:)), keyEquivalent: "q")
        appMenu.addItem(withTitle: "Restart iGhostty Completely…", action: #selector(AppDelegate.restartCompletely(_:)), keyEquivalent: "")
        let quitAll = appMenu.addItem(withTitle: "Quit iGhostty Completely", action: #selector(AppDelegate.quitCompletely(_:)), keyEquivalent: "q")
        quitAll.keyEquivalentModifierMask = [.command, .option]
        main.addItem(submenuItem("iGhostty", appMenu))

        // Shell menu
        let shell = NSMenu(title: "Shell")
        shell.addItem(withTitle: "New Window", action: #selector(AppDelegate.newWindow(_:)), keyEquivalent: "n")
        shell.addItem(withTitle: "New Tab", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t")

        let newTabProfiles = NSMenu(title: "New Tab with Profile")
        newTabProfiles.identifier = MenuID.newTabProfileMenu
        newTabProfiles.delegate = delegate
        let newTabProfilesItem = NSMenuItem(title: "New Tab with Profile", action: nil, keyEquivalent: "")
        newTabProfilesItem.submenu = newTabProfiles
        shell.addItem(newTabProfilesItem)

        shell.addItem(.separator())
        // ⌥V/⌥H are handled by an event monitor (option+letter never reaches
        // menu equivalents); the visible items display them, hidden alternates
        // keep ⌘D/⇧⌘D live.
        let splitV = shell.addItem(withTitle: "Split Vertically", action: #selector(AppDelegate.splitVertically(_:)), keyEquivalent: "v")
        splitV.keyEquivalentModifierMask = [.option]
        let splitH = shell.addItem(withTitle: "Split Horizontally", action: #selector(AppDelegate.splitHorizontally(_:)), keyEquivalent: "h")
        splitH.keyEquivalentModifierMask = [.option]
        let splitVAlt = shell.addItem(withTitle: "Split Vertically", action: #selector(AppDelegate.splitVertically(_:)), keyEquivalent: "d")
        splitVAlt.isHidden = true
        splitVAlt.allowsKeyEquivalentWhenHidden = true
        let splitHAlt = shell.addItem(withTitle: "Split Horizontally", action: #selector(AppDelegate.splitHorizontally(_:)), keyEquivalent: "d")
        splitHAlt.keyEquivalentModifierMask = [.command, .shift]
        splitHAlt.isHidden = true
        splitHAlt.allowsKeyEquivalentWhenHidden = true
        shell.addItem(.separator())
        shell.addItem(withTitle: "Close", action: #selector(AppDelegate.closeActive(_:)), keyEquivalent: "w")
        let closeTab = shell.addItem(withTitle: "Close All Panes in Tab", action: #selector(AppDelegate.closeAllPanesInTab(_:)), keyEquivalent: "w")
        closeTab.keyEquivalentModifierMask = [.command, .option]
        let closeWin = shell.addItem(withTitle: "Close Window", action: #selector(AppDelegate.closeWholeWindow(_:)), keyEquivalent: "w")
        closeWin.keyEquivalentModifierMask = [.command, .shift]
        main.addItem(submenuItem("Shell", shell))

        // Edit menu
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Clear Buffer", action: #selector(AppDelegate.clearBuffer(_:)), keyEquivalent: "k")
        edit.addItem(.separator())

        let findMenu = NSMenu(title: "Find")
        let find = NSMenuItem(title: "Find…", action: #selector(AppDelegate.findPanelAction(_:)), keyEquivalent: "f")
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        findMenu.addItem(find)
        let findNext = NSMenuItem(title: "Find Next", action: #selector(AppDelegate.findPanelAction(_:)), keyEquivalent: "g")
        findNext.tag = Int(NSFindPanelAction.next.rawValue)
        findMenu.addItem(findNext)
        let findPrev = NSMenuItem(title: "Find Previous", action: #selector(AppDelegate.findPanelAction(_:)), keyEquivalent: "G")
        findPrev.tag = Int(NSFindPanelAction.previous.rawValue)
        findMenu.addItem(findPrev)
        let useSel = NSMenuItem(title: "Use Selection for Find", action: #selector(AppDelegate.findPanelAction(_:)), keyEquivalent: "e")
        useSel.tag = Int(NSFindPanelAction.setFindString.rawValue)
        findMenu.addItem(useSel)
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = findMenu
        edit.addItem(findItem)
        main.addItem(submenuItem("Edit", edit))

        // View menu
        let view = NSMenu(title: "View")
        let bigger = view.addItem(withTitle: "Make Text Bigger", action: #selector(AppDelegate.biggerText(_:)), keyEquivalent: "+")
        bigger.keyEquivalentModifierMask = [.command]
        let biggerAlt = view.addItem(withTitle: "Make Text Bigger", action: #selector(AppDelegate.biggerText(_:)), keyEquivalent: "=")
        biggerAlt.isHidden = true
        biggerAlt.allowsKeyEquivalentWhenHidden = true
        view.addItem(withTitle: "Make Text Smaller", action: #selector(AppDelegate.smallerText(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Default Text Size", action: #selector(AppDelegate.resetTextSize(_:)), keyEquivalent: "0")
        view.addItem(.separator())
        view.addItem(withTitle: "Use Transparency", action: #selector(AppDelegate.toggleUseTransparency(_:)), keyEquivalent: "u")
        let maximize = view.addItem(withTitle: "Maximize Active Pane", action: #selector(AppDelegate.toggleMaximizePane(_:)), keyEquivalent: "\r")
        maximize.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(.separator())
        let scrollTop = view.addItem(withTitle: "Scroll to Top", action: #selector(AppDelegate.scrollToTop(_:)), keyEquivalent: String(UnicodeScalar(NSHomeFunctionKey)!))
        scrollTop.keyEquivalentModifierMask = [.command]
        let scrollEnd = view.addItem(withTitle: "Scroll to End", action: #selector(AppDelegate.scrollToEnd(_:)), keyEquivalent: String(UnicodeScalar(NSEndFunctionKey)!))
        scrollEnd.keyEquivalentModifierMask = [.command]
        view.addItem(.separator())
        view.addItem(withTitle: "Toggle Drop-down Terminal", action: #selector(AppDelegate.toggleDropdown(_:)), keyEquivalent: "")
        view.addItem(.separator())
        let fullScreen = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        // iTerm2's classic full-screen toggle.
        let fullScreenAlt = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "\r")
        fullScreenAlt.keyEquivalentModifierMask = [.command]
        fullScreenAlt.isHidden = true
        fullScreenAlt.allowsKeyEquivalentWhenHidden = true
        main.addItem(submenuItem("View", view))

        // Session menu (iTerm2 defaults: ⌘I, ⌥⌘I)
        let session = NSMenu(title: "Session")
        session.addItem(withTitle: "Edit Session…", action: #selector(AppDelegate.editSession(_:)), keyEquivalent: "i")
        session.addItem(.separator())
        let broadcast = session.addItem(withTitle: "Broadcast Input to All Panes in Tab", action: #selector(AppDelegate.toggleBroadcastInput(_:)), keyEquivalent: "i")
        broadcast.keyEquivalentModifierMask = [.command, .option]
        session.addItem(.separator())
        session.addItem(withTitle: "Reset Terminal", action: #selector(AppDelegate.resetTerminal(_:)), keyEquivalent: "r")
        session.addItem(withTitle: "Restart Session", action: #selector(AppDelegate.restartSession(_:)), keyEquivalent: "")
        session.addItem(.separator())
        let previousPrompt = session.addItem(withTitle: "Jump to Previous Prompt", action: #selector(AppDelegate.jumpToPreviousPrompt(_:)), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        previousPrompt.keyEquivalentModifierMask = [.command]
        let nextPrompt = session.addItem(withTitle: "Jump to Next Prompt", action: #selector(AppDelegate.jumpToNextPrompt(_:)), keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        nextPrompt.keyEquivalentModifierMask = [.command]
        main.addItem(submenuItem("Session", session))

        // Profiles menu (rebuilt dynamically)
        let profiles = NSMenu(title: "Profiles")
        profiles.identifier = MenuID.profilesMenu
        profiles.delegate = delegate
        main.addItem(submenuItem("Profiles", profiles))

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let prevTab = windowMenu.addItem(withTitle: "Show Previous Tab", action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "[")
        prevTab.keyEquivalentModifierMask = [.command, .shift]
        let nextTab = windowMenu.addItem(withTitle: "Show Next Tab", action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "]")
        nextTab.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(withTitle: "Move Tab to New Window", action: #selector(NSWindow.moveTabToNewWindow(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Merge All Windows", action: #selector(NSWindow.mergeAllWindows(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())

        // Pane navigation
        for (title, key, dir) in [
            ("Select Pane Above", String(UnicodeScalar(NSUpArrowFunctionKey)!), "up"),
            ("Select Pane Below", String(UnicodeScalar(NSDownArrowFunctionKey)!), "down"),
            ("Select Pane Left", String(UnicodeScalar(NSLeftArrowFunctionKey)!), "left"),
            ("Select Pane Right", String(UnicodeScalar(NSRightArrowFunctionKey)!), "right"),
        ] {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.selectPane(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command, .option]
            item.representedObject = dir
            windowMenu.addItem(item)
        }
        windowMenu.addItem(withTitle: "Select Next Pane", action: #selector(AppDelegate.selectNextPane(_:)), keyEquivalent: "]")
        windowMenu.addItem(withTitle: "Select Previous Pane", action: #selector(AppDelegate.selectPreviousPane(_:)), keyEquivalent: "[")
        windowMenu.addItem(.separator())

        // ⌘1…⌘9 tab selection (hidden items carry the key equivalents).
        for n in 1...9 {
            let item = NSMenuItem(title: "Select Tab \(n)", action: #selector(AppDelegate.selectTabNumber(_:)), keyEquivalent: "\(n)")
            item.tag = n
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            windowMenu.addItem(item)
        }
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        main.addItem(submenuItem("Window", windowMenu))
        NSApp.windowsMenu = windowMenu

        // Help menu
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "iGhostty README", action: #selector(AppDelegate.openReadme(_:)), keyEquivalent: "")
        help.addItem(withTitle: "Open Settings Folder", action: #selector(AppDelegate.revealSettingsFolder(_:)), keyEquivalent: "")
        main.addItem(submenuItem("Help", help))
        NSApp.helpMenu = help

        return main
    }

    private static func submenuItem(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
