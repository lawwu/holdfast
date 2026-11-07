import Foundation

// One binary, three faces: the window (`mackb app`, or launched as MacKB.app),
// the MCP server (`mackb mcp`), and the command line (everything else).
configureMLXMemory()
let launchedAsApp = Bundle.main.bundlePath.hasSuffix(".app")
if launchedAsApp, CommandLine.arguments.dropFirst().first == "listen" {
    // `mackb listen --app/--system` relaunched inside Holdfast.app (Listen.relayThroughApp), so macOS
    // asks Holdfast for System Audio Recording. No window: it runs the command and exits.
    Task {
        await runCLI()
        exit(0)
    }
    dispatchMain()
} else if launchedAsApp || CommandLine.arguments.dropFirst().first == "app" {
    MacKBApp.main()
} else {
    Task {
        await runCLI()
        exit(0)
    }
    dispatchMain()
}
