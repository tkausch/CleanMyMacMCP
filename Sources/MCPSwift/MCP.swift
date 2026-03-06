//
// This File belongs to SwiftRestEssentials 
// Copyright © 2026 Thomas Kausch.
// All Rights Reserved.

import Foundation
import MCP



@main
struct HelloWorldServer {
    static func main() async throws {
        // Create server with tools capability
        let server = Server(
            name: "swift-mcp",
            version: "1.0.0",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )
        
        // Register tool list handler
        await server.withMethodHandler(ListTools.self) { _ in
            let tools = [
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
            return .init(tools: tools)
        }
        
        // Register tool call handler
        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            
            case "swift_version":
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["swift", "--version"]
                
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
                        content: [.text("Error running swift: \(error.localizedDescription)")],
                        isError: true
                    )
                }
            
            case "disk_usage":
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["df", "-h"]
                
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
                            content: [.text("Failed to decode disk usage output")],
                            isError: true
                        )
                    }
                } catch {
                    return .init(
                        content: [.text("Error running df: \(error.localizedDescription)")],
                        isError: true
                    )
                }

            case "file_size":
                // Extract file path from arguments
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
                    
                    // Format the size in a human-readable way
                    let formatter = ByteCountFormatter()
                    formatter.allowedUnits = [.useAll]
                    formatter.countStyle = .file
                    let readableSize = formatter.string(fromByteCount: fileSize)
                    
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

            default:
                return .init(
                    content: [.text("Unknown tool: \(params.name)")],
                    isError: true
                )
            }
        }
        
        // 4️⃣ Start server with stdio transport
             let transport = StdioTransport()
             do {
                 try await server.start(transport: transport)
                 // Keep the server running indefinitely
             } catch {
                 fputs("Server failed: \(error)\n", stderr)
             }
        
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        
    }
}

