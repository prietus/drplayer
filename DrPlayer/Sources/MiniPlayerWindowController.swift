import AppKit
import SwiftUI

final class MiniPlayerWindowController {
    static let shared = MiniPlayerWindowController()

    private var panel: NSPanel?
    private var vm: PlayerViewModel?
    private var mainWindow: NSWindow?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(vm: PlayerViewModel) {
        if let panel, panel.isVisible {
            close()
        } else {
            show(vm: vm)
        }
    }

    func show(vm: PlayerViewModel) {
        self.vm = vm

        if let panel {
            panel.orderFront(nil)
            return
        }

        let view = MiniPlayerView(vm: vm, onClose: { [weak self] in self?.close() })
        let hostingView = NSHostingView(rootView: view)
        hostingView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        hostingView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Restore saved position or center on screen
        let key = "MiniPlayerFrame"
        if let saved = UserDefaults.standard.string(forKey: key) {
            panel.setFrame(from: saved)
        } else {
            panel.center()
        }

        // Save position on move
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { _ in
            UserDefaults.standard.set(panel.frameDescriptor, forKey: key)
        }

        // Restore main window if panel is closed via X button
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            if let main = self?.mainWindow {
                main.deminiaturize(nil)
                self?.mainWindow = nil
            }
            self?.panel = nil
        }

        panel.orderFront(nil)
        self.panel = panel

        // Minimize main window
        if let main = NSApp.windows.first(where: { $0 !== panel && !$0.isMiniaturized && $0.isVisible && !($0 is NSPanel) }) {
            mainWindow = main
            main.miniaturize(nil)
        }
    }

    func close() {
        panel?.close()
        panel = nil

        // Restore main window
        if let main = mainWindow {
            main.deminiaturize(nil)
            mainWindow = nil
        }
    }
}
