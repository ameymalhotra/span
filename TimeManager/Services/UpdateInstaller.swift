import AppKit
import Foundation
import Observation

/// Downloads a release and replaces the running app with it.
///
/// A user who has the app open should not have to visit a web page, find the
/// right file and drag it over the copy they are already running. The one thing
/// this cannot do is replace a bundle while it is executing, so the swap is
/// handed to a small script that waits for Span to quit, exchanges the bundles
/// and opens the new one.
@MainActor
@Observable
final class UpdateInstaller {

    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double)
        case preparing
        /// Everything is staged; quitting now completes the swap.
        case readyToRestart
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private var stagedApp: URL?

    /// Where the running app lives, and whether it can be replaced in place.
    private var bundleURL: URL { Bundle.main.bundleURL }

    var canInstall: Bool {
        FileManager.default.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path)
    }

    func install(from asset: URL) async {
        guard canInstall else {
            phase = .failed("Span cannot replace itself where it is installed. Move it to Applications and try again.")
            return
        }

        do {
            phase = .downloading(fraction: 0)
            let dmg = try await download(asset)

            phase = .preparing
            let app = try mountAndStage(dmg)
            stagedApp = app
            phase = .readyToRestart
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Quits Span and lets the helper put the new copy in place.
    func restartIntoUpdate() {
        guard let stagedApp else { return }
        do {
            try launchSwapHelper(replacing: bundleURL, with: stagedApp)
            NSApp.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        phase = .idle
        if let stagedApp {
            try? FileManager.default.removeItem(at: stagedApp.deletingLastPathComponent())
        }
        stagedApp = nil
    }

    // MARK: - Steps

    private func download(_ asset: URL) async throws -> URL {
        let (stream, response) = try await URLSession.shared.bytes(from: asset)
        let expected = response.expectedContentLength
        var data = Data()
        if expected > 0 { data.reserveCapacity(Int(expected)) }

        var lastReported = 0.0
        for try await byte in stream {
            data.append(byte)
            guard expected > 0 else { continue }
            let fraction = Double(data.count) / Double(expected)
            // Repainting per byte would cost more than the download.
            if fraction - lastReported > 0.02 {
                lastReported = fraction
                phase = .downloading(fraction: fraction)
            }
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("span-update-\(UUID().uuidString).dmg")
        try data.write(to: destination)
        return destination
    }

    /// Mounts the image, copies the app out, and unmounts — so nothing depends
    /// on the disk image still being attached when the swap happens.
    private func mountAndStage(_ dmg: URL) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("span-update-\(UUID().uuidString)", isDirectory: true)
        let mount = staging.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly",
                                     "-mountpoint", mount.path])
        defer {
            try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
            try? FileManager.default.removeItem(at: dmg)
        }

        let source = mount.appendingPathComponent("Span.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw UpdateError.message("The downloaded disk image did not contain Span.")
        }
        let staged = staging.appendingPathComponent("Span.app")
        try FileManager.default.copyItem(at: source, to: staged)
        return staged
    }

    private func launchSwapHelper(replacing target: URL, with staged: URL) throws {
        let script = """
        #!/bin/sh
        # Wait for Span to exit before touching the bundle it is running from.
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(target.path)"
        cp -R "\(staged.path)" "\(target.path)"
        # A self-downloaded file carries no quarantine, but strip it defensively.
        xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null
        open "\(target.path)"
        rm -rf "\(staged.deletingLastPathComponent().path)"
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("span-update-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [url.path]
        try process.run()
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.message(String(data: output, encoding: .utf8) ?? "\(tool) failed")
        }
        return String(data: output, encoding: .utf8) ?? ""
    }

    private enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): text }
        }
    }
}
