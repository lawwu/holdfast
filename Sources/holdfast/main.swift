import Foundation

// One binary, three faces: the window (`holdfast app`, or launched as Holdfast.app),
// the MCP server (`holdfast mcp`), and the command line (everything else).
let launchedAsApp = Bundle.main.bundlePath.hasSuffix(".app")
let firstArgument = CommandLine.arguments.dropFirst().first
if firstArgument == "--version" {
    print("Holdfast " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"))
    exit(0)
}
Migrate.fromOldName(app: launchedAsApp)
configureMLXMemory()
if firstArgument == "app" || (launchedAsApp && (firstArgument == nil || firstArgument!.hasPrefix("-psn"))) {
    HoldfastApp.main()
} else {
    // Explicit commands also work from the installed app, including audio capture
    // with the app's macOS permissions. Opening the app normally shows its window.
    Task {
        await runCLI()
        exit(0)
    }
    dispatchMain()
}
