import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 178)
            Rectangle().fill(RetroPalette.darkEdge).frame(width: 1)
            VStack(spacing: 0) {
                TitleBar()
                Rectangle().fill(RetroPalette.darkEdge).frame(height: 1)
                Group {
                    switch model.section {
                    case .download: DownloadView()
                    case .music: MusicView()
                    case .themes: ThemesView()
                    case .setup: SetupView()
                    case .cookies: CookiesView()
                    case .troubleshooting: TroubleshootingView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(RetroPalette.darkEdge).frame(height: 1)
                ActivityConsole()
                    .frame(height: 224)
            }
        }
        .background(RetroPalette.desktop)
        .foregroundStyle(RetroPalette.ink)
        .sheet(isPresented: $model.showCommandReview) {
            CommandReviewSheet()
                .environmentObject(model)
        }
        .alert("MediaDock 9", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .task { model.refreshDependencies() }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .overlay(Rectangle().stroke(RetroPalette.darkEdge, lineWidth: 1))
                Text("MEDIADOCK 9")
                    .font(.retro(13, weight: .black))
                    .tracking(0.8)
                Text("MEDIA UTILITY · 0.3")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .padding(.top, 18)
            .padding(.bottom, 20)

            ForEach(AppSection.allCases) { section in
                Button {
                    model.section = section
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.symbol)
                            .frame(width: 15)
                        Text(section.rawValue)
                        Spacer()
                        if model.section == section {
                            Rectangle().fill(RetroPalette.ink).frame(width: 5, height: 5)
                        }
                    }
                    .font(.retro(12, weight: model.section == section ? .bold : .regular))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                    .background(model.section == section ? RetroPalette.paper : Color.clear)
                }
                .buttonStyle(.plain)
                .foregroundStyle(RetroPalette.ink)
                Rectangle().fill(RetroPalette.midEdge.opacity(0.55)).frame(height: 1)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    StatusLight(color: model.isBusy ? RetroPalette.cyan : RetroPalette.green)
                    Text(model.isBusy ? "WORKING" : "READY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                Text("Commands stay visible.\nNothing installs silently.")
                    .font(.retro(10))
                    .foregroundStyle(RetroPalette.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RetroPalette.chrome)
    }
}

private struct TitleBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.section.rawValue)
                    .font(.retro(16, weight: .bold))
                Text(subtitle)
                    .font(.retro(10))
                    .foregroundStyle(RetroPalette.ink.opacity(0.66))
            }
            Spacer()
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("CHECKING TOOLS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(RetroPalette.paper)
    }

    private var subtitle: String {
        switch model.section {
        case .download: return "One link in; a visible command out."
        case .music: return "Choose what album downloads should produce."
        case .themes: return "Change the desk without changing what its buttons do."
        case .setup: return "Detect, install, and update the tools MediaDock orchestrates."
        case .cookies: return "Account access stays in your browser or in a file you choose."
        case .troubleshooting: return "Start with versions, then isolate account and network failures."
        }
    }
}

private struct ActivityConsole: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                StatusLight(color: lightColor)
                Text(model.activityItem)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                if model.isBusy {
                    Button("Stop") { model.stopCurrentWork() }
                        .buttonStyle(RetroButtonStyle())
                }
                Button("Copy command") { model.copy(model.runner.activeCommand) }
                    .buttonStyle(RetroButtonStyle())
                Button("Export log") { model.exportLog() }
                    .buttonStyle(RetroButtonStyle())
                Button("Clear") { model.runner.clear() }
                    .buttonStyle(RetroButtonStyle())
                    .disabled(model.runner.isRunning)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RetroPalette.chrome)

            if let progress = model.activityProgress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(RetroPalette.field)
                        Rectangle().fill(RetroPalette.cyan).frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 4)
            } else {
                Rectangle().fill(RetroPalette.midEdge).frame(height: 1)
            }

            LogScroller(entries: model.runner.entries)
        }
        .background(Color(red: 0.10, green: 0.11, blue: 0.11))
    }

    private var lightColor: Color {
        if model.isBusy { return RetroPalette.cyan }
        if model.albumMergeService.stage == .failed { return RetroPalette.red }
        if let code = model.runner.lastExitCode, code != 0 { return RetroPalette.red }
        return RetroPalette.green
    }
}

private struct LogScroller: View {
    let entries: [LogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if entries.isEmpty {
                        Text("Activity log is empty. Commands and tool output will appear here.")
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    ForEach(entries) { entry in
                        Text(entry.text)
                            .foregroundStyle(color(for: entry.kind))
                            .textSelection(.enabled)
                            .id(entry.id)
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .onChange(of: entries.count) {
                if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: LogKind) -> Color {
        switch kind {
        case .command: return RetroPalette.cyan
        case .success: return Color(red: 0.45, green: 0.92, blue: 0.52)
        case .error: return Color(red: 1.0, green: 0.52, blue: 0.46)
        case .info: return Color(red: 0.95, green: 0.82, blue: 0.45)
        case .output: return Color.white.opacity(0.86)
        }
    }
}

private struct CommandReviewSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.reviewTitle)
                .font(.retro(18, weight: .bold))
            Text("These commands can install or update software. Nothing runs until you confirm below.")
                .font(.retro(12))

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.pendingCommands) { command in
                        RetroPanel(title: command.name) {
                            Text(command.displayCommand)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .insetBorder()
                            Text(command.explanation)
                                .font(.retro(11))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    model.pendingCommands = []
                    model.showCommandReview = false
                }
                .buttonStyle(RetroButtonStyle())
                Spacer()
                Button("Run shown commands") { model.runReviewedCommands() }
                    .buttonStyle(RetroButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .frame(width: 680, height: 520)
        .background(RetroPalette.paper)
    }
}
