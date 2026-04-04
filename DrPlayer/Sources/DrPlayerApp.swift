import SwiftUI
import AppKit

@main
struct DrPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            PlayerView()
                .frame(minWidth: 600, minHeight: 500)
        }
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DrPlayer") {
                    NSApp.orderFrontStandardAboutPanel(options: aboutOptions)
                }
            }
            CommandGroup(after: .windowArrangement) {
                Button("Mini Player") {
                    if let vm = PlayerViewModel.current {
                        MiniPlayerWindowController.shared.toggle(vm: vm)
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }

    private var aboutOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: "DrPlayer",
            .applicationVersion: "1.8.2",
            .version: "1",
            .credits: NSAttributedString(
                string: "A music player for people who care about editions.\n\nBitperfect MPD playback with collector-grade metadata.\nBrowse by label, producer, engineer, edition and format.\n\nBuilt with SwiftUI, MPD, MusicBrainz, Discogs, Last.fm and Wikipedia.\n\nLicensed under GPLv3\nhttps://github.com/prietus/drplayer",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ),
            .applicationIcon: NSImage(named: NSImage.applicationIconName) ?? NSImage()
        ]
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Critical: set activation policy to regular so the app gets its own
        // menu bar and can receive keyboard focus when launched from terminal
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
