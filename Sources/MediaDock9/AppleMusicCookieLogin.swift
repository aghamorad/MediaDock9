import SwiftUI
import WebKit

@MainActor
final class AppleMusicCookieLogin: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var status = "Sign in to Apple Music, then save this session."
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    private let dataStore = WKWebsiteDataStore.nonPersistent()
    private var webView: WKWebView?
    var onSaved: ((URL) -> Void)?

    func browserView() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://music.apple.com")!))
        self.webView = webView
        return webView
    }

    func saveSession() {
        isSaving = true
        errorMessage = nil
        status = "Saving this local Apple Music session…"
        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self else { return }
                do {
                    let url = try CookieImportStore.installAppleMusicCookies(from: cookies)
                    self.isSaving = false
                    self.status = "Apple Music session saved locally."
                    self.onSaved?(url)
                } catch {
                    self.isSaving = false
                    self.errorMessage = error.localizedDescription
                    self.status = "The session was not saved."
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status = "When Apple Music looks signed in, press Save session."
    }
}

struct AppleMusicCookieLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var login = AppleMusicCookieLogin()
    let didInstall: (URL) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Sign in to Apple Music")
                .font(.retro(15, weight: .bold))
            Text("This is a temporary, local browser inside MediaDock. Sign in normally, wait until your Apple Music library is visible, then save the session. MediaDock writes only Apple-owned cookies to its protected local file. It does not upload them.")
                .font(.retro(10))
                .fixedSize(horizontal: false, vertical: true)
            AppleMusicWebView(login: login)
                .frame(minWidth: 760, minHeight: 540)
                .insetBorder()
            Text(login.status)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let error = login.errorMessage {
                Text(error)
                    .font(.retro(10))
                    .foregroundStyle(RetroPalette.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(RetroButtonStyle())
                Spacer()
                Button("Save session") { login.saveSession() }
                    .buttonStyle(RetroButtonStyle(prominent: true))
                    .disabled(login.isSaving)
            }
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 690)
        .onAppear {
            login.onSaved = { url in
                didInstall(url)
                dismiss()
            }
        }
    }
}

private struct AppleMusicWebView: NSViewRepresentable {
    let login: AppleMusicCookieLogin

    func makeNSView(context: Context) -> WKWebView { login.browserView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
