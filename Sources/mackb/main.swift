import Foundation

// One binary, three faces: the window (`mackb app`, or launched as MacKB.app),
// the MCP server (`mackb mcp`), and the command line (everything else).
let launchedAsApp = Bundle.main.bundlePath.hasSuffix(".app")
if launchedAsApp || CommandLine.arguments.dropFirst().first == "app" {
    MacKBApp.main()
} else {
    Task {
        await runCLI()
        exit(0)
    }
    dispatchMain()
}
