import Foundation

// One binary, three faces: the window (`holdfast app`, or launched as Holdfast.app),
// the MCP server (`holdfast mcp`), and the command line (everything else).
let launchedAsApp = Bundle.main.bundlePath.hasSuffix(".app")
Migrate.fromOldName(app: launchedAsApp)
configureMLXMemory()
if launchedAsApp, CommandLine.arguments.dropFirst().first == "listen" {
    // `holdfast listen --app/--system` relaunched inside Holdfast.app (Listen.relayThroughApp), so macOS
    // asks Holdfast for System Audio Recording. No window: it runs the command and exits.
    Task {
        await runCLI()
        exit(0)
    }
    dispatchMain()
} else if launchedAsApp || CommandLine.arguments.dropFirst().first == "app" {
    HoldfastApp.main()
} else {
    Task {
        await runCLI()
        exit(0)
    }
    dispatchMain()
}
