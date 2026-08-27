import Foundation
import Combine

struct AlbumMergeRequest {
    let albumDirectory: URL
    let artist: String?
    let album: String?
    let keepIndividualTracks: Bool
    let ffmpegPath: String
    let ffprobePath: String
    let artworkURL: URL?
    let releaseYear: String?
}

@MainActor
final class AlbumMergeService: ObservableObject {
    enum Stage: Equatable {
        case idle, preparing, merging, verifying, completed, failed, cancelled
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var currentItem = "Idle"
    @Published private(set) var progress: Double?
    @Published private(set) var trackCount = 0
    @Published private(set) var totalDuration: TimeInterval?
    @Published private(set) var lastResult: AlbumMergeResult?

    private var process: Process?
    private var cancelled = false
    private var task: Task<Void, Never>?
    private(set) var lastRequest: AlbumMergeRequest?
    var log: ((String, LogKind) -> Void)?

    static let audioExtensions: Set<String> = ["m4a", "aac", "mp3", "flac", "wav", "alac"]

    func mergeAlbum(_ request: AlbumMergeRequest, completion: ((AlbumMergeResult) -> Void)? = nil) {
        cancel()
        lastRequest = request
        lastResult = nil
        cancelled = false
        task = Task { [weak self] in
            guard let self else { return }
            let result = await self.performMerge(request)
            self.lastResult = result
            self.stage = result.cancelled ? .cancelled : (result.success ? .completed : .failed)
            self.currentItem = result.cancelled ? "Stopped" : (result.success ? "One Track, One Album complete" : "One Track, One Album failed")
            self.progress = result.success ? 1 : self.progress
            self.process = nil
            completion?(result)
        }
    }

    func cancel() {
        guard stage == .preparing || stage == .merging || stage == .verifying else { return }
        cancelled = true
        process?.interrupt()
    }

    var isRunning: Bool { stage == .preparing || stage == .merging || stage == .verifying }

    func resetResult() { lastResult = nil; stage = .idle; currentItem = "Idle"; progress = nil }

    func recordFailure(_ message: String) {
        let result = AlbumMergeResult(success: false, outputPath: nil, usedStreamCopy: false, usedFallbackEncoding: false, sourceDuration: nil, outputDuration: nil, trackCount: 0, error: message, cancelled: false)
        lastResult = result; stage = .failed; currentItem = "One Track, One Album failed"; log?("[OneTrackOneAlbum] \(message)", .error)
    }

    static func discoverAudioTracks(in directory: URL, excluding outputURL: URL? = nil) -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        let excluded = outputURL?.standardizedFileURL.path
        return urls.filter { url in
            guard audioExtensions.contains(url.pathExtension.lowercased()), url.standardizedFileURL.path != excluded else { return false }
            let lower = url.lastPathComponent.lowercased()
            return ![".part", ".partial", ".tmp", ".temp", ".download", ".ytdl", ".frag"].contains(where: { lower.hasSuffix($0) })
        }.sorted { naturalFilenameLess($0.lastPathComponent, $1.lastPathComponent) }
    }

    static func naturalFilenameLess(_ lhs: String, _ rhs: String) -> Bool {
        func chunks(_ value: String) -> [String] {
            var result: [String] = []
            var current = ""
            var numeric: Bool?
            for character in value {
                let isNumeric = character.isNumber
                if let numeric, numeric != isNumeric, !current.isEmpty { result.append(current); current = "" }
                numeric = isNumeric
                current.append(character)
            }
            if !current.isEmpty { result.append(current) }
            return result
        }
        let a = chunks(lhs.lowercased()), b = chunks(rhs.lowercased())
        for (x, y) in zip(a, b) where x != y {
            if let xi = Int(x), let yi = Int(y), xi != yi { return xi < yi }
            return x.localizedStandardCompare(y) == .orderedAscending
        }
        return a.count < b.count
    }

    static func sanitizedFilename(artist: String, album: String) -> String {
        let raw = "\(artist) - \(album)"
        let invalid = CharacterSet(charactersIn: "/:\\")
        let cleaned = raw.unicodeScalars.map { invalid.contains($0) || $0.properties.generalCategory == .control ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return (cleaned.isEmpty ? "Merged Album" : cleaned) + ".m4a"
    }

    static func resolveAlbumDirectory(in outputRoot: URL, beforePaths: Set<String> = []) -> URL? {
        let fm = FileManager.default
        var candidates: [(URL, Int, Date)] = []
        guard let enumerator = fm.enumerator(at: outputRoot, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]), values.isDirectory == true else { continue }
            let tracks = discoverAudioTracks(in: url)
            guard !tracks.isEmpty else { continue }
            let changed = tracks.filter { !beforePaths.contains($0.standardizedFileURL.path) }.count
            candidates.append((url, changed, values.contentModificationDate ?? .distantPast))
        }
        if let changed = candidates.filter({ $0.1 > 0 }).max(by: { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 < $1.1 }) { return changed.0 }
        return candidates.max(by: { $0.2 < $1.2 })?.0 ?? (discoverAudioTracks(in: outputRoot).isEmpty ? nil : outputRoot)
    }

    private struct ProcessOutcome { let status: Int32; let output: String }

    private func performMerge(_ request: AlbumMergeRequest) async -> AlbumMergeResult {
        stage = .preparing
        currentItem = "Preparing album…"
        log?("[OneTrackOneAlbum] Album detected: \(request.album ?? request.albumDirectory.lastPathComponent)", .info)
        let initialTracks = Self.discoverAudioTracks(in: request.albumDirectory)
        guard !initialTracks.isEmpty else { return failure("No supported audio tracks were found in the album folder.", count: 0) }
        let tags = await probeTags(initialTracks[0], using: request.ffprobePath)
        let artist = request.artist ?? tags["album_artist"] ?? tags["artist"] ?? request.albumDirectory.deletingLastPathComponent().lastPathComponent
        let album = request.album ?? tags["album"] ?? request.albumDirectory.lastPathComponent
        let outputName = Self.sanitizedFilename(artist: artist, album: album)
        let outputURL = request.albumDirectory.appendingPathComponent(outputName)
        let tracks = await orderedTracks(Self.discoverAudioTracks(in: request.albumDirectory, excluding: outputURL), using: request.ffprobePath)
        trackCount = tracks.count
        guard !tracks.isEmpty else { return failure("No supported audio tracks were found in the album folder.", count: 0) }
        log?("[OneTrackOneAlbum] Found \(tracks.count) audio files", .info)

        let manifestURL = FileManager.default.temporaryDirectory.appendingPathComponent("mediadock-concat-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: manifestURL) }
        do {
            let lines = tracks.map { "file '\(Self.manifestPath($0))'" }.joined(separator: "\n") + "\n"
            try lines.write(to: manifestURL, atomically: true, encoding: .utf8)
        } catch { return failure("Could not create the temporary merge manifest: \(error.localizedDescription)", count: tracks.count) }

        var durations: [TimeInterval] = []
        for track in tracks {
            guard !cancelled else { return cancelledResult(count: tracks.count) }
            guard let duration = await probeDuration(track, using: request.ffprobePath) else { return failure("FFprobe could not read \(track.lastPathComponent).", count: tracks.count) }
            durations.append(duration)
        }
        totalDuration = durations.reduce(0, +)
        stage = .merging
        currentItem = "One Track, One Album… \(tracks.count) / \(tracks.count) tracks · \(Self.durationLabel(totalDuration)) total"
        progress = 0
        log?("[OneTrackOneAlbum] Track order resolved", .info)
        log?("[OneTrackOneAlbum] Attempting stream copy", .info)
        let metadata = Self.metadataArguments(artist: artist, album: album, year: request.releaseYear ?? tags["date"] ?? tags["year"])
        let base = ["-hide_banner", "-loglevel", "warning", "-y", "-f", "concat", "-safe", "0", "-i", manifestURL.path, "-map", "0:a:0", "-vn"]
        let copy = await runProcess(executable: request.ffmpegPath, arguments: base + ["-c:a", "copy"] + metadata + [outputURL.path])
        let usedCopy = copy.status == 0
        var usedFallback = false
        if copy.status != 0 {
            try? FileManager.default.removeItem(at: outputURL)
            log?("[OneTrackOneAlbum] Stream copy failed", .info)
            log?("[OneTrackOneAlbum] Retrying with AAC 256 kbps", .info)
            usedFallback = true
            let fallback = await runProcess(executable: request.ffmpegPath, arguments: base + ["-c:a", "aac", "-b:a", "256k"] + metadata + [outputURL.path])
            if fallback.status != 0 { try? FileManager.default.removeItem(at: outputURL); return failure("FFmpeg could not merge this album.", count: tracks.count, copy: false, fallback: true, source: totalDuration) }
        }
        guard !cancelled else { try? FileManager.default.removeItem(at: outputURL); return cancelledResult(count: tracks.count, source: totalDuration) }
        stage = .verifying
        currentItem = "Verifying…"
        let outputSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard FileManager.default.fileExists(atPath: outputURL.path), outputSize > 0,
              let outputDuration = await probeDuration(outputURL, using: request.ffprobePath) else {
            try? FileManager.default.removeItem(at: outputURL)
            return failure("The merged file could not be verified.", count: tracks.count, copy: usedCopy, fallback: usedFallback, source: totalDuration)
        }
        guard abs((totalDuration ?? 0) - outputDuration) <= 3 else {
            try? FileManager.default.removeItem(at: outputURL)
            return failure("The merged duration did not match the source tracks.", count: tracks.count, copy: usedCopy, fallback: usedFallback, source: totalDuration, output: outputDuration)
        }
        log?("[OneTrackOneAlbum] Source duration: \(totalDuration ?? 0)", .info)
        log?("[OneTrackOneAlbum] Output duration: \(outputDuration)", .info)
        log?("[OneTrackOneAlbum] Verification passed", .success)
        if let artwork = request.artworkURL ?? Self.findArtwork(in: request.albumDirectory) {
            await attemptArtwork(artwork, on: outputURL, using: request.ffmpegPath)
        }
        if !request.keepIndividualTracks {
            for track in tracks { try? FileManager.default.removeItem(at: track) }
        }
        log?("[OneTrackOneAlbum] Complete", .success)
        return AlbumMergeResult(success: true, outputPath: outputURL.path, usedStreamCopy: usedCopy, usedFallbackEncoding: usedFallback, sourceDuration: totalDuration, outputDuration: outputDuration, trackCount: tracks.count, error: nil, cancelled: false)
    }

    private func probeDuration(_ url: URL, using executable: String) async -> TimeInterval? {
        let result = await runProcess(executable: executable, arguments: ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.path])
        return result.status == 0 ? Double(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
    }

    private static func findArtwork(in directory: URL) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        return urls.first { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
    }

    private func attemptArtwork(_ artwork: URL, on output: URL, using executable: String) async {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("mediadock-artwork-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temp) }
        let args = ["-hide_banner", "-loglevel", "warning", "-y", "-i", output.path, "-i", artwork.path, "-map", "0:a:0", "-map", "1:v:0", "-map_metadata", "0", "-c:a", "copy", "-c:v", "copy", "-disposition:v:0", "attached_pic", temp.path]
        let result = await runProcess(executable: executable, arguments: args)
        let size = (try? temp.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard result.status == 0, size > 0 else {
            log?("[OneTrackOneAlbum] Artwork embedding failed; retaining the verified audio.", .info)
            return
        }
        do {
            try FileManager.default.removeItem(at: output)
            try FileManager.default.moveItem(at: temp, to: output)
            log?("[OneTrackOneAlbum] Artwork embedded", .info)
        } catch {
            log?("[OneTrackOneAlbum] Artwork embedding could not replace the output; retaining the verified audio.", .info)
        }
    }

    private func probeTags(_ url: URL, using executable: String) async -> [String: String] {
        let result = await runProcess(executable: executable, arguments: ["-v", "error", "-show_entries", "format_tags=artist,album,album_artist,date,year", "-of", "json", url.path])
        guard result.status == 0, let data = result.output.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let format = object["format"] as? [String: Any], let rawTags = format["tags"] as? [String: String] else { return [:] }
        return Dictionary(uniqueKeysWithValues: rawTags.map { ($0.key.lowercased(), $0.value) })
    }

    private func orderedTracks(_ urls: [URL], using executable: String) async -> [URL] {
        struct Key { let disc: Int?; let track: Int?; let url: URL }
        var keys: [Key] = []
        for url in urls {
            let tags = await probeTags(url, using: executable)
            func number(_ names: [String]) -> Int? {
                for name in names where tags[name] != nil {
                    if let value = tags[name]?.split(separator: "/").first, let number = Int(value) { return number }
                }
                return nil
            }
            keys.append(Key(disc: number(["discnumber", "disc"]), track: number(["tracknumber", "track"]), url: url))
        }
        return keys.sorted { lhs, rhs in
            if let ld = lhs.disc, let rd = rhs.disc, ld != rd { return ld < rd }
            if lhs.disc != nil && rhs.disc == nil { return true }
            if lhs.disc == nil && rhs.disc != nil { return false }
            if let lt = lhs.track, let rt = rhs.track, lt != rt { return lt < rt }
            if lhs.track != nil && rhs.track == nil { return true }
            if lhs.track == nil && rhs.track != nil { return false }
            return Self.naturalFilenameLess(lhs.url.lastPathComponent, rhs.url.lastPathComponent)
        }.map(\.url)
    }

    private func runProcess(executable: String, arguments: [String]) async -> ProcessOutcome {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<ProcessOutcome, Never>) in
                let process = Process(), pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = RuntimeEnvironment.processEnvironment
                process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
                process.terminationHandler = { [weak self] finished in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let outcome = ProcessOutcome(status: finished.terminationStatus, output: String(decoding: data, as: UTF8.self))
                    Task { @MainActor in self?.process = nil; continuation.resume(returning: outcome) }
                }
                self.process = process
                do { try process.run() } catch { self.process = nil; continuation.resume(returning: ProcessOutcome(status: -1, output: error.localizedDescription)) }
            }
        }, onCancel: { [weak self] in Task { @MainActor in self?.process?.interrupt() } })
    }

    private static func manifestPath(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func metadataArguments(artist: String, album: String, year: String?) -> [String] {
        var args = ["-metadata", "title=\(album)", "-metadata", "album=\(album)", "-metadata", "artist=\(artist)", "-metadata", "album_artist=\(artist)"]
        if let year, !year.isEmpty { args += ["-metadata", "date=\(year)"] }
        return args
    }

    private static func durationLabel(_ duration: TimeInterval?) -> String {
        guard let duration else { return "--:--" }
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    private func failure(_ error: String, count: Int, copy: Bool = false, fallback: Bool = false, source: TimeInterval? = nil, output: TimeInterval? = nil) -> AlbumMergeResult {
        log?("[OneTrackOneAlbum] \(error)", .error)
        return AlbumMergeResult(success: false, outputPath: nil, usedStreamCopy: copy, usedFallbackEncoding: fallback, sourceDuration: source, outputDuration: output, trackCount: count, error: error, cancelled: false)
    }

    private func cancelledResult(count: Int, source: TimeInterval? = nil) -> AlbumMergeResult {
        log?("[OneTrackOneAlbum] Merge cancelled; individual tracks were preserved.", .error)
        return AlbumMergeResult(success: false, outputPath: nil, usedStreamCopy: false, usedFallbackEncoding: false, sourceDuration: source, outputDuration: nil, trackCount: count, error: "Merge cancelled.", cancelled: true)
    }
}
