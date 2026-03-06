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
            name: "swift-mcp",
            version: "1.0.0",
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
                name: "swift_version",
                description: "Returns the current Swift version by running 'swift --version'",
                inputSchema: .object([
                    "type": .string("object")
                ])
            ),
            Tool(
                name: "disk_usage",
                description: "Returns disk usage information for all mounted volumes on the Mac",
                inputSchema: .object([
                    "type": .string("object")
                ])
            ),
            Tool(
                name: "file_size",
                description: "Returns the size of a specific file",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Path to the file to check size")
                        ])
                    ]),
                    "required": .array([.string("path")])
                ])
            )
        ]
    }
    
    // MARK: - Tool Call Handler
    
    static func registerToolCallHandler(_ server: Server) async {
        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "swift_version":
                return await executeSwiftVersionTool()
            case "disk_usage":
                return await executeDiskUsageTool()
            case "file_size":
                return await executeFileSizeTool(params: params)
            default:
                return .init(
                    content: [.text("Unknown tool: \(params.name)")],
                    isError: true
                )
            }
        }
    }
    
    // MARK: - Tool Implementations
    
    static func executeSwiftVersionTool() async -> CallTool.Result {
        return await runCommand(
            executable: "/usr/bin/env",
            arguments: ["swift", "--version"],
            errorMessage: "Error running swift"
        )
    }
    
    static func executeDiskUsageTool() async -> CallTool.Result {
        return await runCommand(
            executable: "/usr/bin/env",
            arguments: ["df", "-h"],
            errorMessage: "Error running df"
        )
    }
    
    static func executeFileSizeTool(params: CallTool.Parameters) async -> CallTool.Result {
        guard let arguments = params.arguments,
              case let .string(filePath) = arguments["path"] else {
            return .init(
                content: [.text("Missing or invalid 'path' parameter")],
                isError: true
            )
        }
        
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: filePath)
            
            guard let fileSize = fileAttributes[.size] as? Int64 else {
                return .init(
                    content: [.text("Could not determine file size")],
                    isError: true
                )
            }
            
            let readableSize = formatFileSize(fileSize)
            let response = """
            File: \(filePath)
            Size: \(fileSize) bytes (\(readableSize))
            """
            
            return .init(
                content: [.text(response)],
                isError: false
            )
            
        } catch {
            return .init(
                content: [.text("Error accessing file: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    // MARK: - Helper Methods
    
    static func runCommand(executable: String, arguments: [String], errorMessage: String) async -> CallTool.Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return .init(
                    content: [.text(output.trimmingCharacters(in: .whitespacesAndNewlines))],
                    isError: false
                )
            } else {
                return .init(
                    content: [.text("Failed to decode output")],
                    isError: true
                )
            }
        } catch {
            return .init(
                content: [.text("\(errorMessage): \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    static func formatFileSize(_ fileSize: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
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

