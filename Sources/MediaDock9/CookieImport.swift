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

    static func removeManagedAppleMusicCookies() throws {
        guard FileManager.default.fileExists(atPath: appleMusicCookieURL.path) else { return }
        try FileManager.default.removeItem(at: appleMusicCookieURL)
    }

    static func isManagedPath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == appleMusicCookieURL.standardizedFileURL.path
    }
}
