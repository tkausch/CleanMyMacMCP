# CleanMyMacMCP

A Swift implementation of a Model Context Protocol (MCP) server that helps an AI assistant analyze and clean up disk space on macOS.

## Overview

This project implements an MCP server in Swift that exposes read-only inspection tools plus reversible cleanup actions. An MCP client (e.g. Claude Desktop) uses these tools to find where disk space is going and to suggest what is safe to remove.

The server provides these tools:

| Tool | Type | Purpose |
|------|------|---------|
| `disk_usage` | read-only | Free/used space for all mounted volumes (`df -h`) |
| `directory_sizes` | read-only | Size of each immediate child of a directory, largest first |
| `largest_files` | read-only | Largest individual files under a directory tree |
| `scan_known_junk` | read-only | Sizes of well-known cache / log / build-artifact locations with a safe-to-delete note |
| `list_time_machine_backups` | read-only | Local APFS Time Machine snapshots per volume, with their dates (`tmutil listlocalsnapshots`) |
| `move_to_trash` | destructive | Moves a path to the macOS Trash — **dry run unless `confirm: true`** |
| `delete_time_machine_backup` | destructive | Deletes a local Time Machine snapshot by date — **dry run unless `confirm: true`** |

## What is MCP?

Model Context Protocol (MCP) is a standardized way for AI models to interact with external tools and data sources. This server acts as a bridge between an AI model and your macOS system, letting the model inspect disk usage and (only on explicit confirmation) move items to the Trash.

## Requirements

- macOS 13+
- Swift 6.2+ toolchain (Xcode 16+)
- [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) 0.12.1+ (resolved automatically)

## Installation

1. Clone this repository:
   ```bash
   git clone git@github.com:tkausch/CleanMyMacMCP.git
   cd CleanMyMacMCP
   ```

2. Build the project:
   ```bash
   swift build -c release
   ```
   The executable is produced at:
   ```
   .build/arm64-apple-macosx/release/cleanmymac-mcp
   ```

3. (Optional) Run it directly to check it starts:
   ```bash
   swift run cleanmymac-mcp
   ```
   The server communicates over stdio and waits for MCP protocol messages on stdin.

## Full Disk Access

Several tools read paths under `~/Library`. macOS blocks that by default. Grant **Full Disk Access** in
**System Settings → Privacy & Security → Full Disk Access** to whichever process launches the server
(Claude Desktop, Terminal, or the `cleanmymac-mcp` binary itself). Without it, protected paths report a size of
`0` or are skipped.

## Tools

### `disk_usage`

Disk usage for all mounted volumes.

- **Parameters:** none

```
Filesystem      Size   Used  Avail Capacity   Mounted on
/dev/disk3s1s1  926Gi  455Gi  469Gi    50%    /
```

### `directory_sizes`

Size of each immediate child of a directory, sorted largest first, with a total. Use it to find where space is going.

- `path` (string, optional) — directory to inspect. Defaults to `$HOME`. A leading `~` is expanded.
- `limit` (integer, optional) — max entries to return. Default `40`.

```
Directory sizes under /Users/you/Repos:

  12.39 GB  twint-walletapp-ios
 951.8 MB   CleanMyMacMCP
 805.8 MB   EVSESwift
…
Total of listed children: 18.56 GB
```

### `largest_files`

Largest individual files under a directory tree, sorted largest first.

- `path` (string, optional) — directory to scan recursively. Defaults to `$HOME`. `~` is expanded.
- `min_size_mb` (integer, optional) — ignore files smaller than this. Default `100`.
- `limit` (integer, optional) — max files to return. Default `20`.

```
Largest files under /Users/you/Repos/CleanMyMacMCP (≥ 5 MB):

   70.7 MB  …/.build/…/pack-2df10fe5….pack
   67.1 MB  …/.build/…/index/db/v13/…/data.mdb
```

### `scan_known_junk`

Scans a curated list of macOS cache, log and build-artifact locations and reports the size of each with a
note on how safe it is to delete, plus an approximate total.

- **Parameters:** none

Locations checked include: user caches, Xcode DerivedData / iOS DeviceSupport / Archives, CoreSimulator
caches, Homebrew / CocoaPods / npm / Yarn / pip / Gradle caches, user logs, iOS device backups, Trash and
Downloads.

```
   6.35 GB  User caches
            /Users/you/Library/Caches
            Safe to delete; apps rebuild these.

  35.59 GB  Xcode iOS DeviceSupport
            /Users/you/Library/Developer/Xcode/iOS DeviceSupport
            Safe; re-downloaded when you attach a device with that iOS version.

Approximate total reclaimable: 42.1 GB
```

### `move_to_trash`

Moves a file or directory to the macOS Trash. The move is reversible (restore from Trash until it is emptied).

- `path` (string, required) — absolute or `~`-relative path.
- `confirm` (boolean, optional) — `false`/omitted performs a **dry run** and only reports what would be
  moved and its size. `true` performs the move.

Guard rails:
- Refuses any path outside your home directory.
- Refuses your home directory itself.
- Uses `FileManager.trashItem`, so items land in Trash rather than being deleted outright.

```
DRY RUN — nothing was moved.
Would move to Trash: /Users/you/Library/Developer/Xcode/DerivedData
Size: 165.3 MB
Re-run with "confirm": true to move it.
```

## Client Integration

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "cleanmymac-mcp": {
      "command": "/Users/thomaskausch/Repos/CleanMyMacMCP/.build/arm64-apple-macosx/release/cleanmymac-mcp"
    }
  }
}
```

Update the path to your checkout, build first with `swift build -c release`, then restart Claude Desktop.

### Claude Code

Build the release binary first:

```bash
swift build -c release
```

Then register the server with the `claude` CLI. Use `--scope user` to make it
available in every project, or `--scope local` (the default) for the current
project only:

```bash
claude mcp add cleanmymac-mcp --scope user \
  -- /Users/thomaskausch/Repos/CleanMyMacMCP/.build/arm64-apple-macosx/release/cleanmymac-mcp
```

Alternatively, let Claude Code build and run it on demand:

```bash
claude mcp add cleanmymac-mcp --scope user \
  -- swift run --package-path /Users/thomaskausch/Repos/CleanMyMacMCP -c release cleanmymac-mcp
```

Verify and manage the registration:

```bash
claude mcp list            # show configured servers and their status
claude mcp get cleanmymac-mcp
claude mcp remove cleanmymac-mcp
```

Inside a session, `/mcp` shows the connection status and the tools the server
exposes. To share the configuration with a repo, add it with `--scope project`,
which writes a checked-in `.mcp.json`:

```json
{
  "mcpServers": {
    "cleanmymac-mcp": {
      "command": "/Users/thomaskausch/Repos/CleanMyMacMCP/.build/arm64-apple-macosx/release/cleanmymac-mcp"
    }
  }
}
```

Remember to grant the launching process **Full Disk Access** (see above) or the
`~/Library` scans return `0`.

### Generic stdio client

```json
{
  "servers": {
    "cleanmymac-mcp": {
      "command": "swift",
      "args": ["run", "cleanmymac-mcp"],
      "cwd": "/path/to/CleanMyMacMCP"
    }
  }
}
```

## Development

### Project structure

```
CleanMyMacMCP/
├── Sources/
│   └── CleanMyMacMCP/
│       └── MCP.swift          # Server + all tool implementations
├── Package.swift              # SwiftPM configuration
└── README.md
```

### Key components

- **Server setup** (`createServer`) — MCP server advertising the `tools` capability.
- **Tool registration** (`createAvailableTools`) — tool names, JSON schemas and annotations
  (`readOnlyHint` on the scanners, `destructiveHint` on `move_to_trash`).
- **Tool handlers** (`execute…Tool`) — the actual logic; shell-outs go through `runProcess`,
  which returns captured stdout/stderr and tolerates non-zero exits (e.g. `du`/`find` hitting
  permission-denied subdirectories).
- **Transport** — `StdioTransport`.

### Adding a new tool

1. Add a `Tool(...)` entry in `createAvailableTools()`.
2. Add a `case` in `registerToolCallHandler` dispatching to a new `execute…Tool` function.
3. Return `CallTool.Result` with `content` and `isError`; use `errorResult(_:)` for failures.

Planned incremental additions: `xcode_cruft`, `dev_artifacts` (find `node_modules` / `.build` / `Pods`),
`homebrew_cleanup_preview`, `docker_disk_usage`, `time_machine_snapshots`, `duplicate_files`,
`cleanup_report` (aggregated prioritized suggestions).

## Security considerations

- Read-only tools only run `df`, `du`, `find` and `stat` and never modify anything.
- `move_to_trash` is the only mutating tool: it is dry-run by default, is constrained to the user's home
  directory, and uses the Trash rather than permanent deletion.
- No tool uses `sudo`; everything runs with the launching user's permissions.
- Input paths are validated for existence and type before use.

## License

This project belongs to SwiftRestEssentials.
Copyright © 2026 Thomas Kausch. All Rights Reserved.

## Support

For questions or issues, please open an issue on GitHub.
