import Foundation

enum CookieImportError: LocalizedError {
    case sourceMissing
    case sourceIsDirectory
    case unsupportedFile
    case noAppleMusicCookies
    case destinationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing: return "The selected cookie file no longer exists."
        case .sourceIsDirectory: return "Choose a cookie file, not a folder."
        case .unsupportedFile: return "Choose a Netscape/Mozilla cookie export, usually named cookies.txt."
        case .noAppleMusicCookies: return "MediaDock could not find any Apple Music cookies in this local sign-in window. Finish signing in at music.apple.com, wait for the library page to load, then press Save session again."
        case .destinationUnavailable(let detail): return "MediaDock could not prepare its local cookie storage: \(detail)"
        }
    }
}

enum BrowserCookieError: LocalizedError {
    case databaseNotFound(browser: BrowserChoice, searched: [URL])
    case profileNotUsable(browser: BrowserChoice, profile: URL)

    var errorDescription: String? {
        switch self {
        case let .databaseNotFound(browser, searched):
            let locations = searched.map(\.path).joined(separator: "\n")
            return "MediaDock could not find a " + browser.label + " cookie database. It searched:\n" + locations + "\n\nSign in to music.apple.com in that browser, open it once, then quit that browser and try Extract again. If this browser keeps its session in a different profile, use Choose browser profile. MediaDock cannot extract a session from a browser extension or an open web page when macOS does not expose a local cookie database."
        case let .profileNotUsable(browser, profile):
            return "The selected " + browser.label + " profile does not contain a usable cookie database:\n" + profile.path + "\n\nChoose the profile folder that contains Cookies or Network/Cookies, then try again."
        }
    }
}

enum CookieImportStore {
    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("MediaDock9", isDirectory: true)
            .appendingPathComponent("credentials", isDirectory: true)
    }

    static var appleMusicCookieURL: URL {
        directoryURL.appendingPathComponent("apple-music-cookies.txt")
    }

    /// Returns a yt-dlp browser specification that points at a real local profile.
    /// Passing the profile path avoids yt-dlp falling back to a missing default
    /// profile when a browser uses a non-default or secondary profile.
    static func browserSpecifier(for browser: BrowserChoice, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> String {
        let fm = FileManager.default
        switch browser {
        case .safari:
            let locations = [
                homeDirectory.appendingPathComponent("Library/Cookies/Cookies.binarycookies"),
                homeDirectory.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")
            ]
            guard locations.contains(where: { fm.fileExists(atPath: $0.path) }) else {
                throw BrowserCookieError.databaseNotFound(browser: browser, searched: locations)
            }
            return browser.rawValue
        case .firefox:
            let root = homeDirectory.appendingPathComponent("Library/Application Support/Firefox/Profiles", isDirectory: true)
            let profiles = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            let candidates = profiles.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && fm.fileExists(atPath: url.appendingPathComponent("cookies.sqlite").path)
            }.sorted { modificationDate(of: $0, fileManager: fm) > modificationDate(of: $1, fileManager: fm) }
            if let profile = candidates.first {
                return browser.rawValue + ":" + profile.path
            }
            throw BrowserCookieError.databaseNotFound(browser: browser, searched: [root])
        default:
            let root = chromiumRoot(for: browser, homeDirectory: homeDirectory)
            let searched = [root, root.appendingPathComponent("Default/Cookies"), root.appendingPathComponent("Default/Network/Cookies")]
            let profileDirectories = ([root] + ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []))
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            let cookieDatabases = profileDirectories.flatMap { profile in
                [profile.appendingPathComponent("Cookies"), profile.appendingPathComponent("Network/Cookies")]
            }.filter { fm.fileExists(atPath: $0.path) }
            guard let database = cookieDatabases.max(by: { modificationDate(of: $0, fileManager: fm) < modificationDate(of: $1, fileManager: fm) }) else {
                throw BrowserCookieError.databaseNotFound(browser: browser, searched: searched)
            }
            let profile = database.deletingLastPathComponent().lastPathComponent == "Network"
                ? database.deletingLastPathComponent().deletingLastPathComponent()
                : database.deletingLastPathComponent()
            return try browserSpecifier(for: browser, profileDirectory: profile)
        }
    }

    /// Uses a profile selected by the user only after confirming that it is a real
    /// browser profile.  The app stores the folder path, never its cookie data.
    static func browserSpecifier(for browser: BrowserChoice, profileDirectory: URL) throws -> String {
        guard browser != .safari else { return browser.rawValue }
        let fm = FileManager.default
        let hasCookieDatabase: Bool
        if browser == .firefox {
            hasCookieDatabase = fm.fileExists(atPath: profileDirectory.appendingPathComponent("cookies.sqlite").path)
        } else {
            hasCookieDatabase = fm.fileExists(atPath: profileDirectory.appendingPathComponent("Cookies").path)
                || fm.fileExists(atPath: profileDirectory.appendingPathComponent("Network/Cookies").path)
        }
        guard hasCookieDatabase else { throw BrowserCookieError.profileNotUsable(browser: browser, profile: profileDirectory) }
        return browser.rawValue + ":" + profileDirectory.standardizedFileURL.path
    }

    static func firstAvailableBrowser() -> BrowserChoice? {
        BrowserChoice.allCases.first { (try? browserSpecifier(for: $0)) != nil }
    }

    static func availableBrowsers(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [BrowserChoice] {
        BrowserChoice.allCases.filter { (try? browserSpecifier(for: $0, homeDirectory: homeDirectory)) != nil }
    }

    static func browserRoot(for browser: BrowserChoice, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let support = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        switch browser {
        case .chrome: return support.appendingPathComponent("Google/Chrome", isDirectory: true)
        case .chromium: return support.appendingPathComponent("Chromium", isDirectory: true)
        case .brave: return support.appendingPathComponent("BraveSoftware/Brave-Browser", isDirectory: true)
        case .edge: return support.appendingPathComponent("Microsoft Edge", isDirectory: true)
        case .vivaldi: return support.appendingPathComponent("Vivaldi", isDirectory: true)
        default: return support.appendingPathComponent(browser.rawValue, isDirectory: true)
        }
    }

    private static func chromiumRoot(for browser: BrowserChoice, homeDirectory: URL) -> URL {
        browserRoot(for: browser, homeDirectory: homeDirectory)
    }

    private static func modificationDate(of url: URL, fileManager: FileManager) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    static func importAppleMusicCookies(from sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else { throw CookieImportError.sourceMissing }
        guard !isDirectory.boolValue else { throw CookieImportError.sourceIsDirectory }
        guard sourceURL.pathExtension.lowercased() == "txt" || sourceURL.lastPathComponent.lowercased().contains("cookie") else { throw CookieImportError.unsupportedFile }

        do {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            let temporaryURL = directoryURL.appendingPathComponent(".apple-music-cookies-\(UUID().uuidString).tmp")
            try? fm.removeItem(at: temporaryURL)
            try fm.copyItem(at: sourceURL, to: temporaryURL)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            try? fm.removeItem(at: appleMusicCookieURL)
            try fm.moveItem(at: temporaryURL, to: appleMusicCookieURL)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: appleMusicCookieURL.path)
            return appleMusicCookieURL
        } catch {
            throw CookieImportError.destinationUnavailable(error.localizedDescription)
        }
    }

    static func extractionURL() throws -> URL {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            return directoryURL.appendingPathComponent(".apple-music-cookies-extract-\(UUID().uuidString).txt")
        } catch {
            throw CookieImportError.destinationUnavailable(error.localizedDescription)
        }
    }

    static func installExtractedAppleMusicCookies(from temporaryURL: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: temporaryURL.path) else { throw CookieImportError.sourceMissing }
        do {
            try? fm.removeItem(at: appleMusicCookieURL)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            try fm.moveItem(at: temporaryURL, to: appleMusicCookieURL)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: appleMusicCookieURL.path)
            return appleMusicCookieURL
        } catch {
            throw CookieImportError.destinationUnavailable(error.localizedDescription)
        }
    }

    /// Converts only Apple-owned cookies from the app's temporary WebKit sign-in
    /// window into the Netscape format Gamdl accepts. Cookie values are written
    /// straight to protected local storage and are never logged or displayed.
    static func installAppleMusicCookies(from browserCookies: [HTTPCookie]) throws -> URL {
        let contents = try netscapeCookieExport(from: browserCookies)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            let temporaryURL = directoryURL.appendingPathComponent(".apple-music-cookies-webkit-\(UUID().uuidString).tmp")
            try? fm.removeItem(at: temporaryURL)
            try contents.write(to: temporaryURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            try? fm.removeItem(at: appleMusicCookieURL)
            try fm.moveItem(at: temporaryURL, to: appleMusicCookieURL)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: appleMusicCookieURL.path)
            return appleMusicCookieURL
        } catch {
            throw CookieImportError.destinationUnavailable(error.localizedDescription)
        }
    }

    static func netscapeCookieExport(from browserCookies: [HTTPCookie]) throws -> Data {
        let relevant = browserCookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == "apple.com" || domain.hasSuffix(".apple.com")
        }
        guard !relevant.isEmpty else { throw CookieImportError.noAppleMusicCookies }

        var lines = ["# Netscape HTTP Cookie File", "# Generated locally by MediaDock 9 from its temporary Apple Music sign-in window."]
        for cookie in relevant.sorted(by: { ($0.domain, $0.name) < ($1.domain, $1.name) }) {
            guard !cookie.name.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" }),
                  !cookie.value.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" }) else { continue }
            let rawDomain = cookie.domain.hasPrefix(".") ? cookie.domain : ".\(cookie.domain)"
            let domain = cookie.isHTTPOnly ? "#HttpOnly_\(rawDomain)" : rawDomain
            let includeSubdomains = rawDomain.hasPrefix(".") ? "TRUE" : "FALSE"
            let expiry = Int(cookie.expiresDate?.timeIntervalSince1970 ?? 0)
            lines.append([domain, includeSubdomains, cookie.path, cookie.isSecure ? "TRUE" : "FALSE", "\(expiry)", cookie.name, cookie.value].joined(separator: "\t"))
        }
        guard lines.count > 2 else { throw CookieImportError.noAppleMusicCookies }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func removeManagedAppleMusicCookies() throws {
        guard FileManager.default.fileExists(atPath: appleMusicCookieURL.path) else { return }
        try FileManager.default.removeItem(at: appleMusicCookieURL)
    }

    static func isManagedPath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == appleMusicCookieURL.standardizedFileURL.path
    }
}
