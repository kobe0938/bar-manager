import AppKit
import ServiceManagement

enum Keys {
    static let collapsed = "collapsed"
    static let autoCollapseSeconds = "auto-collapse-seconds"
    static let autosave = "bar-manager-toggle"
}

let autoCollapseChoices: [(title: String, seconds: Int)] = [
    ("Never", 0), ("5 seconds", 5), ("10 seconds", 10), ("30 seconds", 30), ("1 minute", 60),
]

let chevronSize: CGFloat = 22

final class ActionItem: NSMenuItem {
    var handler: () -> Void = {}

    convenience init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: key)
        self.handler = handler
        target = self
    }

    @objc private func fire() {
        handler()
    }
}

func chevronImage(collapsed: Bool) -> NSImage? {
    let symbol = collapsed ? "chevron.left" : "chevron.right"
    let description = collapsed ? "Show hidden icons" : "Hide icons"
    return NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
        .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
}

// A borderless window that floats over the menu bar. macOS stops drawing a status item once it is
// too wide to fit, so while collapsed the chevron is drawn here instead of in the item.
final class ChevronPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: chevronSize, height: chevronSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        // Fully transparent pixels let clicks fall through to the menu bar, so keep a trace of alpha.
        backgroundColor = NSColor.black.withAlphaComponent(0.02)
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
}

final class ChevronView: NSView {
    var onClick: () -> Void = {}
    var onRightClick: () -> Void = {}
    private let imageView = NSImageView()

    var image: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = .labelColor
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { onClick() }
    override func rightMouseUp(with event: NSEvent) { onRightClick() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private var item: NSStatusItem!
    private let panel = ChevronPanel()
    private let chevronView = ChevronView(frame: NSRect(x: 0, y: 0, width: chevronSize, height: chevronSize))
    private var collapseTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    // Wide enough to push everything left of the item off the menu bar on any attached screen.
    private var collapsedLength: CGFloat {
        NSScreen.screens.map { $0.frame.width }.max() ?? 2000
    }

    private var collapsed: Bool {
        get { defaults.object(forKey: Keys.collapsed) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.collapsed) }
    }

    private var autoCollapseSeconds: Int {
        get { defaults.object(forKey: Keys.autoCollapseSeconds) as? Int ?? 10 }
        set { defaults.set(newValue, forKey: Keys.autoCollapseSeconds) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Keys.autosave
        if let button = item.button {
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Click to hide the icons to the left. Right-click for options. ⌘-drag to move."
        }

        panel.contentView = chevronView
        chevronView.onClick = { [weak self] in self?.setCollapsed(false) }
        chevronView.onRightClick = { [weak self] in
            guard let self else { return }
            self.showMenu(in: self.chevronView)
        }

        let center = NotificationCenter.default
        if let window = item.button?.window {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.refreshPanel()
                })
            }
        }
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            guard let self, self.collapsed else { return }
            self.apply(collapsed: true, autoHide: false)
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshPanel()
        })

        apply(collapsed: collapsed, autoHide: false)
    }

    @objc private func buttonClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = item.button {
            showMenu(in: button)
        } else {
            setCollapsed(!collapsed)
        }
    }

    private func setCollapsed(_ value: Bool) {
        collapsed = value
        apply(collapsed: value)
    }

    private func apply(collapsed: Bool, autoHide: Bool = true) {
        item.button?.image = chevronImage(collapsed: collapsed)
        chevronView.image = chevronImage(collapsed: true)
        if collapsed {
            item.length = collapsedLength
            // The item's window moves to its final place a moment after the length changes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refreshPanel() }
        } else {
            panel.orderOut(nil)
            item.length = NSStatusItem.squareLength
        }
        refreshPanel()
        collapseTimer?.invalidate()
        collapseTimer = nil
        if autoHide { scheduleAutoCollapse() }
    }

    private func refreshPanel() {
        guard collapsed, let button = item.button, let window = button.window else {
            panel.orderOut(nil)
            return
        }
        let screen = window.screen ?? NSScreen.main
        let menuBarHidden = screen.map { $0.visibleFrame.maxY >= $0.frame.maxY } ?? true
        if menuBarHidden {
            panel.orderOut(nil)
            return
        }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = NSRect(x: buttonRect.maxX - chevronSize, y: buttonRect.minY, width: chevronSize, height: buttonRect.height)
        panel.appearance = button.effectiveAppearance
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func scheduleAutoCollapse() {
        guard !collapsed, autoCollapseSeconds > 0 else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(autoCollapseSeconds), repeats: false) { [weak self] _ in
            self?.setCollapsed(true)
        }
    }

    private func showMenu(in view: NSView) {
        let menu = NSMenu()
        menu.addItem(ActionItem(collapsed ? "Show Hidden Icons" : "Hide Icons") { [weak self] in
            guard let self else { return }
            self.setCollapsed(!self.collapsed)
        })

        let autoItem = NSMenuItem(title: "Hide Again After", action: nil, keyEquivalent: "")
        let autoMenu = NSMenu()
        for choice in autoCollapseChoices {
            let choiceItem = ActionItem(choice.title) { [weak self] in
                guard let self else { return }
                self.autoCollapseSeconds = choice.seconds
                self.collapseTimer?.invalidate()
                self.scheduleAutoCollapse()
            }
            choiceItem.state = choice.seconds == autoCollapseSeconds ? .on : .off
            autoMenu.addItem(choiceItem)
        }
        autoItem.submenu = autoMenu
        menu.addItem(autoItem)
        menu.addItem(.separator())

        let loginItem = ActionItem("Launch at Login") { [weak self] in self?.toggleLaunchAtLogin() }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(ActionItem("How to Use…") { [weak self] in self?.showHelp() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Quit Bar Manager", key: "q") { NSApp.terminate(nil) })

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func showHelp() {
        setCollapsed(false)
        let alert = NSAlert()
        alert.messageText = "How to use Bar Manager"
        alert.informativeText = """
        Everything to the left of the chevron is the hidden section.

        Hold ⌘ and drag any icon to the left of the chevron to hide it. \
        Drag it back to the right to show it again.

        Click the chevron to show or hide that section. Right-click it for options.

        To move the chevron, show the hidden icons first, then ⌘-drag it.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
