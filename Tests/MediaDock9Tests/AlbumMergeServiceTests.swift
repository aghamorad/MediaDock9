import XCTest
@testable import MediaDock9

final class AlbumMergeServiceTests: XCTestCase {
    func testNaturalOrderingAndFiltering() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["1 Track.m4a", "10 Track.m4a", "2 Track.m4a", "12 Track.mp3", "cover.jpg", "11 Track.m4a.part", "Artist - Album.m4a"] {
            try Data(name.utf8).write(to: directory.appendingPathComponent(name))
        }
        let tracks = AlbumMergeService.discoverAudioTracks(in: directory, excluding: directory.appendingPathComponent("Artist - Album.m4a"))
        XCTAssertEqual(tracks.map(\.lastPathComponent), ["1 Track.m4a", "2 Track.m4a", "10 Track.m4a", "12 Track.mp3"])
    }

    func testUnicodeFilenamePreserved() {
        XCTAssertEqual(AlbumMergeService.sanitizedFilename(artist: "هنرمند 日本語", album: "آلبوم Café"), "هنرمند 日本語 - آلبوم Café.m4a")
    }

    func testThemeCatalogIsInteractiveAndStable() {
        XCTAssertEqual(MediaDockTheme.allCases.count, 3)
        XCTAssertEqual(MediaDockTheme.allCases.map(\.name), ["Macintosh 1999", "DOS Midnight", "Cyberdeck 2088"])
    }

    func testCookieStoreUsesPrivateManagedLocation() {
        XCTAssertTrue(CookieImportStore.appleMusicCookieURL.path.contains("Application Support/MediaDock9/credentials"))
        XCTAssertTrue(CookieImportStore.isManagedPath(CookieImportStore.appleMusicCookieURL.path))
    }

    func testBrowserSpecifierUsesDetectedChromiumProfile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = home.appendingPathComponent("Library/Application Support/Google/Chrome/Profile 1/Network", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data().write(to: profile.appendingPathComponent("Cookies"))
        defer { try? FileManager.default.removeItem(at: home) }

        let specifier = try CookieImportStore.browserSpecifier(for: .chrome, homeDirectory: home)
        XCTAssertEqual(specifier, "chrome:" + profile.deletingLastPathComponent().path)
    }

    func testBrowserSpecifierExplainsMissingProfile() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try CookieImportStore.browserSpecifier(for: .chromium, homeDirectory: home)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("Chromium"))
            XCTAssertTrue(message.contains("Sign in to music.apple.com"))
        }
    }

    @MainActor
    func testPreferenceMapsToSharedOptions() {
        let defaults = UserDefaults(suiteName: "MediaDock9Tests-\(UUID().uuidString)")!
        let model = AppModel(defaults: defaults)
        model.albumDownloadPreference = .oneTrackOneAlbum
        XCTAssertTrue(model.oneTrackOneAlbum)
        XCTAssertFalse(model.keepIndividualTracks)
        model.albumDownloadPreference = .oneTrackOneAlbumKeepingTracks
        XCTAssertTrue(model.keepIndividualTracks)
        model.albumDownloadPreference = .individualTracks
        XCTAssertFalse(model.oneTrackOneAlbum)
    }

    @MainActor
    func testMergeUsesStreamCopyAndKeepsTracks() async throws {
        let fixture = try makeFixture(fallback: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let request = AlbumMergeRequest(albumDirectory: fixture.directory, artist: "Test Artist", album: "Test Album", keepIndividualTracks: true, ffmpegPath: fixture.ffmpeg.path, ffprobePath: fixture.ffprobe.path, artworkURL: nil, releaseYear: nil)
        let service = AlbumMergeService()
        let result = await merge(service, request: request)
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.usedStreamCopy)
        XCTAssertFalse(result.usedFallbackEncoding)
        XCTAssertEqual(result.trackCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Test Artist - Test Album.m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("01 Track.m4a").path))
    }

    @MainActor
    func testFallbackAndDeleteOnlyAfterVerification() async throws {
        let fixture = try makeFixture(fallback: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let request = AlbumMergeRequest(albumDirectory: fixture.directory, artist: "Test Artist", album: "Test Album", keepIndividualTracks: false, ffmpegPath: fixture.ffmpeg.path, ffprobePath: fixture.ffprobe.path, artworkURL: nil, releaseYear: nil)
        let service = AlbumMergeService()
        let result = await merge(service, request: request)
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.usedFallbackEncoding)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("01 Track.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("02 Track.m4a").path))
    }

    @MainActor
    func testMergeFailurePreservesOriginals() async throws {
        let fixture = try makeFixture(fallback: false, alwaysFail: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let request = AlbumMergeRequest(albumDirectory: fixture.directory, artist: "Test Artist", album: "Test Album", keepIndividualTracks: false, ffmpegPath: fixture.ffmpeg.path, ffprobePath: fixture.ffprobe.path, artworkURL: nil, releaseYear: nil)
        let result = await merge(AlbumMergeService(), request: request)
        XCTAssertFalse(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("01 Track.m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("02 Track.m4a").path))
    }

    private func merge(_ service: AlbumMergeService, request: AlbumMergeRequest) async -> AlbumMergeResult {
        await withCheckedContinuation { continuation in
            service.mergeAlbum(request) { continuation.resume(returning: $0) }
        }
    }

    private struct Fixture { let directory: URL; let ffmpeg: URL; let ffprobe: URL }

    private func makeFixture(fallback: Bool, alwaysFail: Bool = false) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["01 Track.m4a", "02 Track.m4a"] { try Data("source".utf8).write(to: directory.appendingPathComponent(name)) }
        let ffprobe = directory.appendingPathComponent("ffprobe")
        let ffmpeg = directory.appendingPathComponent("ffmpeg")
        let probe = "#!/bin/sh\nlast=\"\"; for arg in \"$@\"; do last=\"$arg\"; done\nif echo \"$*\" | grep -q format_tags; then printf '%s' '{\"format\":{\"tags\":{\"artist\":\"Test Artist\",\"album\":\"Test Album\",\"tracknumber\":\"1\",\"discnumber\":\"1\"}}}'; else case \"$last\" in *'Test Artist - Test Album.m4a') printf '2.0';; *) printf '1.0';; esac; fi\n"
        try probe.write(to: ffprobe, atomically: true, encoding: .utf8)
        let state = directory.appendingPathComponent("state")
        let ffmpegScript = "#!/bin/sh\nlast=\"\"; for arg in \"$@\"; do last=\"$arg\"; done\n\(fallback ? "if [ ! -e '\(state.path)' ]; then touch '\(state.path)'; exit 1; fi\n" : "")\(alwaysFail ? "exit 1\n" : "")printf 'merged' > \"$last\"\n"
        try ffmpegScript.write(to: ffmpeg, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffprobe.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpeg.path)
        return Fixture(directory: directory, ffmpeg: ffmpeg, ffprobe: ffprobe)
    }
}
