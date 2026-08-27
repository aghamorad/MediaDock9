import Foundation

enum CookieImportError: LocalizedError {
    case sourceMissing
    case sourceIsDirectory
    case unsupportedFile
    case destinationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing: return "The selected cookie file no longer exists."
        case .sourceIsDirectory: return "Choose a cookie file, not a folder."
        case .unsupportedFile: return "Choose a Netscape/Mozilla cookie export, usually named cookies.txt."
        case .destinationUnavailable(let detail): return "MediaDock could not prepare its local cookie storage: \(detail)"
        }
    }
}

enum BrowserCookieError: LocalizedError {
    case databaseNotFound(browser: BrowserChoice, searched: [URL])

    var errorDescription: String? {
        switch self {
        case let .databaseNotFound(browser, searched):
            let locations = searched.map(\.path).joined(separator: "\n")
            return "MediaDock could not find a " + browser.label + " cookie database. It searched:\n" + locations + "\n\nSign in to music.apple.com in that browser, open it once, then try Extract again. If you use a different browser, select it first. Chromium-family browsers may need to be quit before extraction so macOS can release the database."
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
            return browser.rawValue + ":" + profile.path
        }
    }

    static func availableBrowsers(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [BrowserChoice] {
        BrowserChoice.allCases.filter { (try? browserSpecifier(for: $0, homeDirectory: homeDirectory)) != nil }
    }

    private static func chromiumRoot(for browser: BrowserChoice, homeDirectory: URL) -> URL {
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

    static func removeManagedAppleMusicCookies() throws {
        guard FileManager.default.fileExists(atPath: appleMusicCookieURL.path) else { return }
        try FileManager.default.removeItem(at: appleMusicCookieURL)
    }

    static func isManagedPath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == appleMusicCookieURL.standardizedFileURL.path
    }
}
