import AppKit
import Darwin
import SwiftUI

@main
struct MediaDock9App: App {
    @StateObject private var model = AppModel()

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
        WindowGroup("MediaDock 9") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 760)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("MediaDock") {
                Button("Rescan Dependencies") { model.refreshDependencies() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Copy Current Command") { model.copy(model.runner.activeCommand) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Divider()
                Button("Stop Current Command") { model.runner.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.runner.isRunning)
            }
        }
    }
}
