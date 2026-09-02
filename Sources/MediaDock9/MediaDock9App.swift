import AppKit
import Darwin
import SwiftUI

@MainActor
final class MediaDockApplicationDelegate: NSObject, NSApplicationDelegate {
    var reopenMainWindow: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        reopenMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

@main
struct MediaDock9App: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(MediaDockApplicationDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--self-test") {
            let failures = SelfCheck.run()
            if failures.isEmpty {
                print("MediaDock 9 self-test: PASS")
                exit(0)
            } else {
                print("MediaDock 9 self-test: FAIL")
                failures.forEach { print("- \($0)") }
                exit(1)
            }
        }
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("MediaDock 9", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 760)
                .preferredColorScheme(.light)
                .onAppear {
                    appDelegate.reopenMainWindow = {
                        openWindow(id: "main")
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open MediaDock Window") { openWindow(id: "main") }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("MediaDock") {
                Button("Rescan Dependencies") { model.refreshDependencies() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Copy Current Command") { model.copy(model.runner.activeCommand) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Divider()
                Button("Stop Current Work") { model.stopCurrentWork() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.isBusy)
            }
        }
    }
}
