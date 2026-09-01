//
// This File belongs to SwiftRestEssentials
// Copyright © 2026 Thomas Kausch.
// All Rights Reserved.

import Foundation
import MCP

@main
struct HelloWorldServer {
    static func main() async throws {
        let server = createServer()
        await registerToolListHandler(server)
        await registerToolCallHandler(server)
        try await startServer(server)
    }

    // MARK: - Server Configuration

    static func createServer() -> Server {
        return Server(
            name: "cleanmymac-mcp",
            version: "2.0.0",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )
    }

    // MARK: - Tool List Handler

    static func registerToolListHandler(_ server: Server) async {
        await server.withMethodHandler(ListTools.self) { _ in
            let tools = createAvailableTools()
            return .init(tools: tools)
        }
    }

    static func createAvailableTools() -> [Tool] {
        return [
            Tool(
                name: "disk_usage",
                description: "Returns disk usage information for all mounted volumes on the Mac",
                inputSchema: .object([
                    "type": .string("object")
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "directory_sizes",
                description: """
                Reports the size of each immediate child of a directory, sorted \
                largest first. Use this to find where disk space is going. \
                Defaults to the user's home directory.
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Directory to inspect. Defaults to $HOME. '~' is expanded.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of entries to return (default 40).")
                        ])
                    ])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "largest_files",
                description: """
                Finds the largest individual files under a directory tree, sorted \
                largest first. Defaults to the user's home directory.
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Directory to scan recursively. Defaults to $HOME. '~' is expanded.")
                        ]),
                        "min_size_mb": .object([
                            "type": .string("integer"),
                            "description": .string("Only consider files at least this many megabytes (default 100).")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of files to return (default 20).")
                        ])
                    ])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "scan_known_junk",
                description: """
                Scans a curated list of well-known macOS cache, log and build-artifact \
                locations and reports the size of each along with a note on how safe it \
                is to delete. Read-only.
                """,
                inputSchema: .object([
                    "type": .string("object")
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "move_to_trash",
                description: """
                Moves a file or directory to the macOS Trash (reversible). \
                DRY RUN BY DEFAULT: without "confirm": true it only reports what would \
                be moved and its size. Pass "confirm": true to actually move it.
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path (or '~'-relative) of the item to trash.")
                        ]),
                        "confirm": .object([
                            "type": .string("boolean"),
                            "description": .string("Set true to perform the move. Omitted/false = dry run.")
                        ])
                    ]),
                    "required": .array([.string("path")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false)
            ),
            Tool(
                name: "list_time_machine_backups",
                description: """
                Lists local Time Machine snapshots (APFS local snapshots stored on \
                the Mac's own disk) for every mounted local volume, with each \
                snapshot's date. These consume local disk space until macOS thins \
                them. Read-only.
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "volume": .object([
                            "type": .string("string"),
                            "description": .string("Mount point to inspect (e.g. '/'). Defaults to every mounted local volume.")
                        ])
                    ])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "delete_time_machine_backup",
                description: """
                Deletes a local Time Machine snapshot by its date (as reported by \
                list_time_machine_backups, e.g. '2026-09-01-123456'). \
                DRY RUN BY DEFAULT: without "confirm": true it only reports what \
                would be deleted. Pass "confirm": true to actually delete it. \
                Deleting a local snapshot does not affect backups on an external \
                Time Machine destination.
                """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "snapshot_date": .object([
                            "type": .string("string"),
                            "description": .string("Snapshot date to delete, e.g. '2026-09-01-123456'.")
                        ]),
                        "confirm": .object([
                            "type": .string("boolean"),
                            "description": .string("Set true to perform the deletion. Omitted/false = dry run.")
                        ])
                    ]),
                    "required": .array([.string("snapshot_date")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
            )
        ]
    }

    // MARK: - Tool Call Handler

    static func registerToolCallHandler(_ server: Server) async {
        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "disk_usage":
                return await executeDiskUsageTool()
            case "directory_sizes":
                return await executeDirectorySizesTool(params: params)
            case "largest_files":
                return await executeLargestFilesTool(params: params)
            case "scan_known_junk":
                return await executeScanKnownJunkTool()
            case "move_to_trash":
                return executeMoveToTrashTool(params: params)
            case "list_time_machine_backups":
                return await executeListTimeMachineBackupsTool(params: params)
            case "delete_time_machine_backup":
                return await executeDeleteTimeMachineBackupTool(params: params)
            default:
                return .init(
                    content: [.text("Unknown tool: \(params.name)")],
                    isError: true
                )
            }
        }
    }

    // MARK: - Tool Implementations

    static func executeDiskUsageTool() async -> CallTool.Result {
        return await runCommand(
            executable: "/usr/bin/env",
            arguments: ["df", "-h"],
            errorMessage: "Error running df"
        )
    }

    static func executeDirectorySizesTool(params: CallTool.Parameters) async -> CallTool.Result {
        let path = resolvedPath(params.arguments?["path"]?.stringValue) ?? homeDirectory
        let limit = params.arguments?["limit"]?.intValue ?? 40

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return errorResult("Not a directory: \(path)")
        }

        // -k: sizes in 1024-byte blocks, -d 1: one level deep.
        let output = await runProcess(
            executable: "/usr/bin/du",
            arguments: ["-k", "-d", "1", path]
        )
        // du exits non-zero on permission-denied subdirs but still prints usable rows.
        let text: String
        switch output {
        case let .success(value): text = value
        case let .failure(value): text = value
        }

        var entries: [(name: String, kb: Int64)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kb = Int64(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            let entryPath = String(parts[1])
            if entryPath == path { continue } // skip the grand total row
            entries.append((name: URL(fileURLWithPath: entryPath).lastPathComponent, kb: kb))
        }
        entries.sort { $0.kb > $1.kb }

        let total = entries.reduce(Int64(0)) { $0 + $1.kb }
        let shown = entries.prefix(limit)
        var lines = ["Directory sizes under \(path):", ""]
        for entry in shown {
            lines.append("\(formatFileSize(entry.kb * 1024).leftPadded(to: 10))  \(entry.name)")
        }
        if entries.count > shown.count {
            lines.append("… \(entries.count - shown.count) smaller entries not shown")
        }
        lines.append("")
        lines.append("Total of listed children: \(formatFileSize(total * 1024))")
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }

    static func executeLargestFilesTool(params: CallTool.Parameters) async -> CallTool.Result {
        let path = resolvedPath(params.arguments?["path"]?.stringValue) ?? homeDirectory
        let minSizeMB = max(1, params.arguments?["min_size_mb"]?.intValue ?? 100)
        let limit = params.arguments?["limit"]?.intValue ?? 20

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return errorResult("Not a directory: \(path)")
        }

        // find … -exec stat prints "<bytes>\t<path>" for each matching file.
        let output = await runProcess(
            executable: "/usr/bin/find",
            arguments: [path, "-type", "f", "-size", "+\(minSizeMB)M",
                        "-exec", "/usr/bin/stat", "-f", "%z\t%N", "{}", "+"]
        )
        let text: String
        switch output {
        case let .success(value): text = value
        case let .failure(message):
            // find exits non-zero on permission errors but still prints partial results.
            text = message
        }

        var files: [(size: Int64, path: String)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let size = Int64(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            files.append((size: size, path: String(parts[1])))
        }
        files.sort { $0.size > $1.size }

        guard !files.isEmpty else {
            return .init(content: [.text("No files ≥ \(minSizeMB) MB found under \(path).")], isError: false)
        }

        var lines = ["Largest files under \(path) (≥ \(minSizeMB) MB):", ""]
        for file in files.prefix(limit) {
            lines.append("\(formatFileSize(file.size).leftPadded(to: 10))  \(file.path)")
        }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }

    static func executeScanKnownJunkTool() async -> CallTool.Result {
        var lines = ["Known cache / junk locations:", ""]
        var grandTotal: Int64 = 0

        for location in knownJunkLocations {
            let expanded = (location.path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else { continue }

            let output = await runProcess(executable: "/usr/bin/du", arguments: ["-sk", expanded])
            var kb: Int64 = 0
            if case let .success(text) = output,
               let first = text.split(separator: "\n").first,
               let value = Int64(first.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "") {
                kb = value
            }
            grandTotal += kb
            lines.append("\(formatFileSize(kb * 1024).leftPadded(to: 10))  \(location.label)")
            lines.append("            \(expanded)")
            lines.append("            \(location.note)")
            lines.append("")
        }

        lines.append("Approximate total reclaimable: \(formatFileSize(grandTotal * 1024))")
        lines.append("")
        lines.append("Note: sizes require Full Disk Access for the host process; without it some paths read as 0 or are skipped.")
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }

    static func executeMoveToTrashTool(params: CallTool.Parameters) -> CallTool.Result {
        guard let rawPath = params.arguments?["path"]?.stringValue, !rawPath.isEmpty else {
            return errorResult("Missing or invalid 'path' parameter")
        }
        let path = (rawPath as NSString).expandingTildeInPath
        let confirm = params.arguments?["confirm"]?.boolValue ?? false

        guard FileManager.default.fileExists(atPath: path) else {
            return errorResult("Path does not exist: \(path)")
        }

        // Guard rail: never touch anything outside the user's home directory.
        guard path == homeDirectory || path.hasPrefix(homeDirectory + "/") else {
            return errorResult("Refusing to trash a path outside your home directory: \(path)")
        }
        guard path != homeDirectory else {
            return errorResult("Refusing to trash your entire home directory.")
        }

        let sizeText = directorySizeText(for: path)

        guard confirm else {
            return .init(content: [.text("""
            DRY RUN — nothing was moved.
            Would move to Trash: \(path)
            Size: \(sizeText)
            Re-run with "confirm": true to move it.
            """)], isError: false)
        }

        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resultingURL)
            let destination = resultingURL?.path ?? "the Trash"
            return .init(content: [.text("""
            Moved to Trash.
            From: \(path)
            Now at: \(destination)
            Freed (once Trash is emptied): \(sizeText)
            """)], isError: false)
        } catch {
            return errorResult("Failed to move to Trash: \(error.localizedDescription)")
        }
    }

    static func executeListTimeMachineBackupsTool(params: CallTool.Parameters) async -> CallTool.Result {
        let volumes: [String]
        if let requested = params.arguments?["volume"]?.stringValue, !requested.isEmpty {
            volumes = [requested]
        } else {
            volumes = localMountPoints()
        }

        var lines = ["Local Time Machine snapshots:", ""]
        var found = 0
        for volume in volumes {
            let output = await runProcess(
                executable: "/usr/bin/tmutil",
                arguments: ["listlocalsnapshots", volume]
            )
            let text: String
            switch output {
            case let .success(value): text = value
            case let .failure(value):
                lines.append("\(volume): \(value.trimmingCharacters(in: .whitespacesAndNewlines))")
                lines.append("")
                continue
            }

            let dates = text
                .split(separator: "\n")
                .compactMap { snapshotDate(fromListingLine: String($0)) }

            guard !dates.isEmpty else { continue }
            lines.append("\(volume):")
            for date in dates {
                lines.append("    \(date)")
                found += 1
            }
            lines.append("")
        }

        if found == 0 {
            lines.append("No local snapshots found.")
        } else {
            lines.append("\(found) local snapshot(s). Delete one with delete_time_machine_backup.")
        }
        lines.append("")
        lines.append("Note: this lists on-disk APFS local snapshots, not backups on an external Time Machine drive.")
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }

    static func executeDeleteTimeMachineBackupTool(params: CallTool.Parameters) async -> CallTool.Result {
        guard let rawDate = params.arguments?["snapshot_date"]?.stringValue, !rawDate.isEmpty else {
            return errorResult("Missing or invalid 'snapshot_date' parameter")
        }
        // Accept either a bare date or a full "com.apple.TimeMachine.<date>.local" name.
        let snapshotDate = snapshotDate(fromListingLine: rawDate) ?? rawDate

        // Basic shape check: YYYY-MM-DD-HHMMSS
        let pattern = #"^\d{4}-\d{2}-\d{2}-\d{6}$"#
        guard snapshotDate.range(of: pattern, options: .regularExpression) != nil else {
            return errorResult("'\(rawDate)' does not look like a snapshot date (expected e.g. 2026-09-01-123456).")
        }

        let confirm = params.arguments?["confirm"]?.boolValue ?? false
        guard confirm else {
            return .init(content: [.text("""
            DRY RUN — nothing was deleted.
            Would delete local snapshot: \(snapshotDate)
            Re-run with "confirm": true to delete it.
            """)], isError: false)
        }

        let output = await runProcess(
            executable: "/usr/bin/tmutil",
            arguments: ["deletelocalsnapshots", snapshotDate]
        )
        switch output {
        case let .success(text):
            return .init(content: [.text("""
            Deleted local snapshot \(snapshotDate).
            \(text.trimmingCharacters(in: .whitespacesAndNewlines))
            """)], isError: false)
        case let .failure(text):
            return errorResult("Failed to delete snapshot \(snapshotDate): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// Extracts a `YYYY-MM-DD-HHMMSS` snapshot date from a `tmutil listlocalsnapshots`
    /// line such as `com.apple.TimeMachine.2026-09-01-123456.local`.
    static func snapshotDate(fromListingLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let pattern = #"\d{4}-\d{2}-\d{2}-\d{6}"#
        guard let range = trimmed.range(of: pattern, options: .regularExpression) else { return nil }
        return String(trimmed[range])
    }

    /// Mount points of local (non-network) mounted volumes.
    static func localMountPoints() -> [String] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) else {
            return ["/"]
        }
        var points = urls.compactMap { url -> String? in
            let isLocal = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal ?? false
            return isLocal ? url.path : nil
        }
        if !points.contains("/") { points.insert("/", at: 0) }
        return points
    }

    // MARK: - Known junk locations

    struct JunkLocation {
        let label: String
        let path: String
        let note: String
    }

    static let knownJunkLocations: [JunkLocation] = [
        .init(label: "User caches", path: "~/Library/Caches",
              note: "Safe to delete; apps rebuild these."),
        .init(label: "Xcode DerivedData", path: "~/Library/Developer/Xcode/DerivedData",
              note: "Safe to delete; regenerated on next build."),
        .init(label: "Xcode iOS DeviceSupport", path: "~/Library/Developer/Xcode/iOS DeviceSupport",
              note: "Safe; re-downloaded when you attach a device with that iOS version."),
        .init(label: "Xcode Archives", path: "~/Library/Developer/Xcode/Archives",
              note: "Review first — needed to re-submit or symbolicate old builds."),
        .init(label: "CoreSimulator caches", path: "~/Library/Developer/CoreSimulator/Caches",
              note: "Safe to delete."),
        .init(label: "Homebrew cache", path: "~/Library/Caches/Homebrew",
              note: "Safe; run 'brew cleanup' for a managed clean."),
        .init(label: "CocoaPods cache", path: "~/Library/Caches/CocoaPods",
              note: "Safe; re-downloaded on next 'pod install'."),
        .init(label: "npm cache", path: "~/.npm/_cacache",
              note: "Safe; 'npm cache clean --force' equivalent."),
        .init(label: "Yarn cache", path: "~/Library/Caches/Yarn",
              note: "Safe to delete."),
        .init(label: "pip cache", path: "~/Library/Caches/pip",
              note: "Safe to delete."),
        .init(label: "Gradle caches", path: "~/.gradle/caches",
              note: "Safe; re-downloaded on next build."),
        .init(label: "User logs", path: "~/Library/Logs",
              note: "Safe to delete."),
        .init(label: "iOS device backups", path: "~/Library/Application Support/MobileSync/Backup",
              note: "Review first — these are your device backups."),
        .init(label: "Trash", path: "~/.Trash",
              note: "Empty when you're sure you don't need the contents."),
        .init(label: "Downloads", path: "~/Downloads",
              note: "Review manually; often full of installers and one-off files."),
    ]

    // MARK: - Helper Methods

    static var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Expands a leading `~` and returns nil for nil/empty input.
    static func resolvedPath(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return (raw as NSString).expandingTildeInPath
    }

    static func errorResult(_ message: String) -> CallTool.Result {
        .init(content: [.text(message)], isError: true)
    }

    enum ProcessOutcome {
        case success(String)
        case failure(String)
    }

    /// Runs a process, returning combined stdout/stderr. `.failure` carries whatever
    /// was captured when the process exits non-zero.
    static func runProcess(executable: String, arguments: [String]) async -> ProcessOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            return process.terminationStatus == 0 ? .success(text) : .failure(text)
        } catch {
            return .failure("\(executable) could not be launched: \(error.localizedDescription)")
        }
    }

    static func runCommand(executable: String, arguments: [String], errorMessage: String) async -> CallTool.Result {
        switch await runProcess(executable: executable, arguments: arguments) {
        case let .success(text):
            return .init(content: [.text(text.trimmingCharacters(in: .whitespacesAndNewlines))], isError: false)
        case let .failure(text):
            let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(content: [.text("\(errorMessage): \(detail)")], isError: true)
        }
    }

    static func directorySizeText(for path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let text = String(data: data, encoding: .utf8),
               let first = text.split(separator: "\n").first,
               let kb = Int64(first.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "") {
                return formatFileSize(kb * 1024)
            }
        } catch {}
        return "unknown"
    }

    static func formatFileSize(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    // MARK: - Server Lifecycle

    static func startServer(_ server: Server) async throws {
        let transport = StdioTransport()
        do {
            try await server.start(transport: transport)
        } catch {
            fputs("Server failed: \(error)\n", stderr)
            throw error
        }

        // Keep the server running indefinitely
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
