# MCPSwift

A Swift implementation of a Model Context Protocol (MCP) server that provides system information and file utilities.

## Overview

This project implements an MCP server in Swift that exposes useful system tools for macOS. The server provides three main tools:

- **Swift Version**: Get the current Swift compiler version
- **Disk Usage**: View disk usage information for all mounted volumes
- **File Size**: Check the size of specific files

## What is MCP?

Model Context Protocol (MCP) is a standardized way for AI models to interact with external tools and data sources. This server acts as a bridge between AI models and your macOS system, allowing models to safely execute system commands and retrieve information.

## Features

- ✅ Swift version checking
- ✅ Disk usage monitoring  
- ✅ File size inspection
- ✅ Secure stdio transport
- ✅ Error handling and validation
- ✅ Human-readable output formatting

## Requirements

- macOS 10.15+ (for Process and FileManager APIs)
- Swift 5.9+
- MCP Swift Package

## Installation

1. Clone this repository:
```bash
git clone git@github.com:tkausch/MCPSwift.git
cd MCPSwift
```

2. Build the project:
```bash
swift build
```

3. Run the server:
```bash
swift run
```

## Usage

### Running the Server

The server communicates over stdio (standard input/output), which is the standard transport method for MCP servers:

```bash
swift run MCPSwift
```

The server will start and wait for MCP protocol messages on stdin.

### Available Tools

#### 1. Swift Version Tool

Returns the current Swift compiler version.

**Tool Name:** `swift_version`
**Description:** Returns the current Swift version by running 'swift --version'
**Parameters:** None

**Example Response:**
```
swift-driver version: 1.87.3 Apple Swift version 5.9.2
```

#### 2. Disk Usage Tool

Shows disk usage information for all mounted volumes on your Mac.

**Tool Name:** `disk_usage`
**Description:** Returns disk usage information for all mounted volumes on the Mac
**Parameters:** None

**Example Response:**
```
Filesystem      Size   Used  Avail Capacity   Mounted on
/dev/disk3s1s1  926Gi  455Gi  469Gi    50%    /
/dev/disk3s6    926Gi  2.0Gi  469Gi     1%    /System/Volumes/VM
```

#### 3. File Size Tool

Returns the size of a specific file in both bytes and human-readable format.

**Tool Name:** `file_size`
**Description:** Returns the size of a specific file
**Parameters:**
- `path` (required): Path to the file to check size

**Example Request:**
```json
{
  "path": "/Users/username/Documents/example.txt"
}
```

**Example Response:**
```
File: /Users/username/Documents/example.txt
Size: 1024 bytes (1 KB)
```

## MCP Protocol Integration

This server implements the MCP specification and can be integrated with MCP-compatible clients. The server supports:

- Tool listing via `tools/list`
- Tool execution via `tools/call`
- Error handling and validation
- Capability negotiation

### Client Integration

#### Using with Claude Desktop

To use this server with Claude Desktop, add the following configuration to your Claude Desktop settings:

1. Open Claude Desktop
2. Go to Settings
3. Add the following to your MCP servers configuration:

```json
"mcpServers": {
  "swift-mcp": {
    "command": "/Users/thomaskausch/Repos/MCPSwift/.build/arm64-apple-macosx/debug/swift-mcp"
  }
}
```

**Note:** Make sure to:
- Build the project first: `swift build`
- Update the path to match your actual project location
- The executable name should match your Swift package target name

#### Generic MCP Client Integration

For other MCP clients, configure it as a stdio transport server:

```json
{
  "servers": {
    "swift-mcp": {
      "command": "swift",
      "args": ["run", "MCPSwift"],
      "cwd": "/path/to/MCPSwift"
    }
  }
}
```

## Development

### Project Structure

```
MCPSwift/
├── Sources/
│   └── MCPSwift/
│       └── MCP.swift          # Main server implementation
├── Package.swift              # Swift Package Manager configuration
└── README.md                  # This file
```

### Key Components

- **Server Setup**: Creates an MCP server with tool capabilities
- **Tool Registration**: Defines available tools and their schemas
- **Tool Handlers**: Implements the actual tool functionality
- **Transport**: Uses stdio for communication

### Adding New Tools

To add a new tool:

1. Add the tool definition in the `ListTools` handler
2. Implement the tool logic in the `CallTool` handler
3. Add appropriate error handling

Example:
```swift
// In ListTools handler
Tool(
    name: "my_new_tool",
    description: "Description of what the tool does",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "parameter": .object([
                "type": .string("string"),
                "description": .string("Parameter description")
            ])
        ]),
        "required": .array([.string("parameter")])
    ])
)

// In CallTool handler
case "my_new_tool":
    // Implementation here
    return .init(
        content: [.text("Tool result")],
        isError: false
    )
```

## Security Considerations

This server executes system commands and accesses the file system. When deploying:

- Run with appropriate user permissions
- Validate all input parameters
- Consider sandboxing for production use
- Monitor for potential security issues

## Error Handling

The server includes comprehensive error handling:

- Invalid tool parameters return descriptive error messages
- System command failures are caught and reported
- File access errors are handled gracefully
- Unknown tools return appropriate error responses

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project belongs to SwiftRestEssentials.
Copyright © 2026 Thomas Kausch. All Rights Reserved.

## Support

For questions or issues, please open an issue on GitHub.