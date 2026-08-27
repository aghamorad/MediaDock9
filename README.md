# MediaDock 9

## Why I made it

I was playing around with Codex and realized that downloading something simple could turn into a scavenger hunt through Terminal commands, Python packages, browser cookies, ChatGPT answers, forums, and Reddit. I wanted to make that part easier for someone who does not want to spend an afternoon figuring out which command belongs where.

So I made MediaDock 9: a small Mac app with an old-school retro interface where you paste a link, choose what you want, see the command before it runs, watch what is happening, and stop it if something goes wrong. I liked the idea of making a practical utility that feels like an actual little application instead of another anonymous settings page.

MediaDock 9 is a native macOS front end for `yt-dlp`, `spotdl`, `gamdl`, FFmpeg, Deno, pipx, and Homebrew. It gives those existing command-line tools a clearer place to live without reimplementing their download or account logic.

The activity console follows the command runner live: running/idle status, current item, progress, controls, and tool output update as the underlying downloader emits them.

Before launching a downloader, MediaDock creates the selected destination if needed and verifies that it is writable. This also ensures Gamdl can initialize its optional SQLite download database before media processing begins.

The first version is deliberately transparent:

- it detects each dependency, version, path, and known package manager;
- it shows the exact command before a download and throughout execution;
- installs and updates require a command-review confirmation sheet;
- stdout and stderr remain visible in a live activity console;
- Stop sends an interrupt so the child tool can clean up;
- existing output files are preserved by default;
- Apple Music cookie contents are never opened or displayed;
- no DRM, token extraction, decryption, wrapper server, or media-transfer implementation lives in this codebase.

Use it only for media you are legally entitled and contractually permitted to download. Apple, Google/YouTube, and Spotify can change their services and terms independently of this project.

## What is included

- [GitHub Releases](https://github.com/aghamorad/MediaDock9/releases/latest) — ready-to-use Apple Silicon app, ad-hoc signed
- `Sources/MediaDock9` — complete SwiftUI/AppKit source
- `Package.swift` — Swift Package project; Xcode can open it directly
- `scripts/build_app.sh` — reproducible command-line `.app` builder
- `Resources/AppIcon-1024.png` — original custom retro icon asset
- `Resources/ICON_PROMPT.md` — the exact built-in image-generation prompt used for the icon
- `Info.plist` — app-bundle metadata and Downloads-folder usage text

## Quick start

Download `MediaDock9-0.3.1-App.zip` from the [latest release](https://github.com/aghamorad/MediaDock9/releases/latest), unzip it, and move **MediaDock 9.app** to Applications.

The app was built for Apple Silicon. Because it is an ad-hoc-signed development build rather than a notarized public release, macOS may initially decline to open it on a different Mac. You can inspect the source and build it locally instead:

```bash
cd /path/to/MediaDock9
./scripts/build_app.sh
```

The script compiles a release executable, assembles the `.app`, copies the icon and `Info.plist`, and applies an ad-hoc signature. It writes only inside this project’s `.build` and `dist` folders.

For development:

```bash
swift run MediaDock9
```

For the non-GUI command-builder check:

```bash
./dist/MediaDock\ 9.app/Contents/MacOS/MediaDock9 --self-test
```

Expected output:

```text
MediaDock 9 self-test: PASS
```

### Build requirements

- macOS 14 or later
- Apple’s current Xcode, or matching Command Line Tools and macOS SDK
- Swift 5.10 or later

The build script keeps compiler caches in the project. It also recognizes the specific situation in which an executable links and passes self-test but a command-line-only toolchain cannot generate its optional `.dSYM`. A full current Xcode installation remains the recommended build environment.

## How the app is organized

| File | Responsibility |
|---|---|
| `MediaDock9App.swift` | app entry point, window, menu commands, `--self-test` route |
| `AppModel.swift` | preferences, validation, command construction, setup/update plans, file panels |
| `CommandRuntime.swift` | executable search path, version scans, process execution, streaming logs, progress, cancellation |
| `Models.swift` | source/format/dependency models and safe shell-display quoting |
| `RootView.swift` | window shell, sidebar, command-review sheet, permanent activity console |
| `MainViews.swift` | Download, Setup, Cookies, and Troubleshooting screens |
| `RetroTheme.swift` | sparse platinum-gray controls, inset/raised borders, status lights, typography |
| `SelfCheck.swift` | isolated checks for URL detection, quoting, and all three command builders |

`AppModel` creates an argument array for `Process`; it does not concatenate user input into a shell command. The shell-quoted text in the interface is a faithful copy/paste representation of that executable and argument array.

## Dependency detection

MediaDock checks these locations, followed by the app’s inherited `PATH`:

```text
/opt/homebrew/bin
/opt/homebrew/sbin
/usr/local/bin
/usr/local/sbin
~/.local/bin
~/Library/Python/3.11–3.13/bin
/usr/bin
/bin
/usr/sbin
/sbin
```

Each version probe has an eight-second limit so a damaged dependency cannot leave Setup spinning forever. Homebrew ownership is checked with `brew list --versions FORMULA`; pipx ownership is checked with `pipx list --short`. A tool found outside its expected manager is marked **External** and Update All leaves it alone.

## Setup and update commands

No command in this section runs until the user presses an Install or Update button, reviews the full batch, and confirms **Run shown commands**.

| Purpose | Command pattern |
|---|---|
| Install Homebrew | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Install native dependency | `brew install pipx`, `ffmpeg`, `deno`, or `yt-dlp` |
| Add pipx app directory to shell path | `pipx ensurepath` |
| Install Python app | `pipx install spotdl` or `pipx install gamdl` |
| Refresh Homebrew index | `brew update` |
| Update one confirmed Brew formula | `brew upgrade FORMULA` |
| Update one confirmed pipx app | `pipx upgrade PACKAGE` |

Homebrew’s own installer may require an administrator password and a real Terminal session. If the GUI process cannot satisfy that prompt, MediaDock leaves the exact official command visible to copy into Terminal; it does not attempt to bypass the prompt.

## Download commands

The interface previews the resolved executable path and every argument. Paths and URLs are shell-quoted for copy/paste, but `Process` receives them as separate arguments.

### YouTube

Base shape:

```bash
yt-dlp --newline --no-overwrites -P OUTPUT [OPTIONS] URL
```

Available controls include:

- video or extracted audio;
- MP4, MKV, or WebM merge container;
- best available or a maximum resolution;
- MP3, M4A, FLAC, Opus, or WAV audio output;
- playlist versus single-item mode and playlist-aware filenames;
- embedded metadata and thumbnail;
- manual and automatic subtitles with a visible language pattern;
- `archive.txt` duplicate history;
- `--cookies-from-browser BROWSER` for authorized sign-in cases.

MediaDock adds `--no-overwrites`. It does not delete partial or existing media files. Current options are grounded in the official [yt-dlp README](https://github.com/yt-dlp/yt-dlp/blob/master/README.md) and [cookie FAQ](https://github.com/yt-dlp/yt-dlp/wiki/FAQ).

### Spotify

Base shape:

```bash
spotdl download URL --format FORMAT --bitrate QUALITY \
  --output 'OUTPUT/{artists} - {title}.{output-ext}' \
  --overwrite skip --print-errors
```

SpotDL does **not** copy the audio stream from Spotify. It reads Spotify metadata, searches its configured audio providers—normally YouTube Music—for a match, downloads that match, then tags the file. MediaDock exposes format, quality, collection numbering, synced LRC generation, and archive handling. A larger requested bitrate cannot restore detail absent from the provider source. See the official [SpotDL usage guide](https://spotdl.github.io/spotify-downloader/usage/).

### Apple Music

Base shape:

```bash
gamdl --temp-path ~/Library/Caches/MediaDock9/gamdl-temp \
  --cookies-path /path/to/cookies.txt \
  --output-path OUTPUT --log-level INFO \
  --song-codec-priority aac-web [OPTIONS] URL
```

Before every Gamdl launch, MediaDock creates `~/Library/Caches/MediaDock9/gamdl-temp` if needed, verifies that it is writable, and passes its absolute path through `--temp-path`. A preparation failure is shown in the app; Full Disk Access is not required. This version intentionally selects the ordinary web codec and does not pass `--use-wrapper`, a WVD path, a wrapper URL, or any locally implemented decryption facility. Gamdl itself owns the account and media workflow; MediaDock only launches the installed executable with visible options.

Controls include music-video resolution, MP4 remuxing, metadata, separate cover files, synced LRC lyrics, collection/artist batch handling, M3U8 playlist output, and a per-output-folder SQLite download database. See Gamdl’s current [official README and option table](https://github.com/glomatico/gamdl).

## Cookies and security model

### YouTube

When enabled, MediaDock passes the selected browser name to yt-dlp’s `--cookies-from-browser` option. MediaDock does not create a cookie export. The underlying tool and browser may trigger macOS privacy or Keychain prompts. Chromium-family browsers can lock their cookie database while running; quitting that browser once may resolve that particular failure.

### Apple Music

Gamdl currently requires an active Apple Music subscription and a Netscape/Mozilla-format browser cookie export in its ordinary cookie-based mode. MediaDock stores only the selected file path in `UserDefaults`.

MediaDock does not:

- read or validate cookie-file contents;
- copy the file into Application Support;
- print it to the command log;
- upload it;
- store Apple or Google passwords.

The exact command necessarily reveals the local cookie-file **path**, never its contents. Treat the file itself like a password: keep it private and delete it when no longer needed.

### Process and filesystem permissions

The app is not sandboxed because its purpose is to find and launch user-installed executables from Homebrew and pipx. It inherits the current user’s permissions. The launched tools perform their own network requests and filesystem writes.

The app itself stores only preferences in `UserDefaults` and writes a log file only when **Export log** is pressed. It may ask for macOS Downloads-folder access when a tool first writes there. Output folders are created by the selected downloader after the explicit Download action.

## Reversibility and failure behavior

- Downloaded files remain ordinary files in the chosen folder.
- Existing media is protected with yt-dlp `--no-overwrites`, SpotDL `--overwrite skip`, and Gamdl’s default no-overwrite behavior.
- Stop sends an interrupt rather than deleting partial work.
- Logs stay in memory until Clear or app exit unless explicitly exported.
- Forget path removes the stored Apple cookie path; it does not delete the cookie file.
- Update All stops at the first non-zero command and does not continue through a failed batch.
- MediaDock does not uninstall dependencies. Use their original package manager if you later choose to remove them.

## Troubleshooting sequence

1. **Rescan and update first.** Service-facing tools change frequently.
2. **Refresh Apple cookies.** Sign in again, export a fresh Netscape-format file, and select it.
3. **Enable YouTube browser cookies only when needed.** Choose the signed-in browser; quit it once if its database is locked.
4. **Isolate read timeouts.** Stop, confirm the site works in a browser, compare normal versus VPN/proxy routing, and retry after updating.
5. **Inspect paths.** If Terminal finds a tool but MediaDock does not, link it into a searched directory or manage it from its original install location.
6. **Export the activity log and copy the diagnostic summary.** The summary excludes pasted URLs and cookie contents.

## Current first-version limits

- One command or update batch runs at a time.
- Progress is parsed from human-readable tool output, so a future upstream log-format change may reduce the percentage display while the raw log remains available.
- The app does not provide an interactive stdin terminal. Apple Music artist links use Gamdl’s automatic `all-albums` selection when collection mode is enabled.
- Spotify/YouTube matching accuracy remains SpotDL’s responsibility.
- The provided app binary is Apple Silicon and not notarized for public distribution.
- Tool options and service behavior were verified against maintainer documentation in August 2026; upstream changes can still require an app update.

## Third-party software

MediaDock 9 does not bundle Homebrew, pipx, FFmpeg, Deno, yt-dlp, SpotDL, or Gamdl. Each is installed separately, remains governed by its own license, and can be updated or removed with its own manager.
