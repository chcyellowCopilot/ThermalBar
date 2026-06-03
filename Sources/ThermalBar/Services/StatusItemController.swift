import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 120)
    private let popover = NSPopover()
    private var store: ThermalStatusStore?
    private var observer: NSObjectProtocol?
    private var detailsWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var globalMonitor: Any?

    func configure(store: ThermalStatusStore) {
        self.store = store

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                store: store,
                openDetails: { [weak self] in self?.showDetailsWindow() },
                openSettingsAction: { [weak self] in self?.showSettingsWindow() }
            )
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }

        observer = NotificationCenter.default.addObserver(
            forName: .menuBarTitleDidChange,
            object: store,
            queue: .main
        ) { [weak self] notification in
            let title = notification.userInfo?["title"] as? String
            let symbol = notification.userInfo?["symbol"] as? String
            let width = notification.userInfo?["width"] as? Double
            Task { @MainActor in
                self?.update(title: title, symbol: symbol, width: width)
            }
        }

        update(title: store.statusBarTitle, symbol: store.menuBarSymbol, width: store.statusBarWidth)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startGlobalMonitor()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        stopGlobalMonitor()
    }

    private func startGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func stopGlobalMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    private func update(title: String?, symbol: String?, width: Double?) {
        guard let store else {
            return
        }

        update(
            title: title ?? store.statusBarTitle,
            symbol: symbol ?? store.menuBarSymbol,
            width: width ?? store.statusBarWidth
        )
    }

    private func update(title: String, symbol: String, width: Double) {
        statusItem.length = width + 10

        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private func showDetailsWindow() {
        guard let store else {
            return
        }

        closePopover()
        if detailsWindow == nil {
            let hostingController = NSHostingController(
                rootView: ContentView(store: store)
                    .frame(minWidth: 520, minHeight: 460)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "ThermalBar 详情"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 520))
            window.center()
            detailsWindow = window
        }

        detailsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettingsWindow() {
        guard let store else {
            return
        }

        closePopover()
        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView(store: store)
                    .frame(width: 420)
                    .padding(.bottom, 4)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "ThermalBar 设置"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 460, height: 440))
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
