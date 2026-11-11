#if HOLDFAST_DEMO_CAPTURE
import AppKit
import SwiftUI

/// Local screenshot driver, compiled only into the separate documentation app.
/// It uses the real views and Store actions, and refuses any vault without the demo marker.
@MainActor
enum DemoCapture {
    private static var timer: Timer?
    private static var lastID = ""
    private static var settings: NSWindow?
    private static var modelWindow: NSWindow?
    private static var importingModel = false
    private static var modelImportError = ""

    static func install(_ store: Store) {
        guard timer == nil,
              let folder = ProcessInfo.processInfo.environment["HOLDFAST_DEMO_CONTROL"],
              (try? String(contentsOf: store.vault.appendingPathComponent(".holdfast-demo"), encoding: .utf8)) == "public sample notes only\n"
        else { return }
        let directory = URL(fileURLWithPath: folder)
        NSApp.appearance = NSAppearance(named: .aqua)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let window = NSApp.windows.first(where: { $0.title == "Holdfast" }) {
                window.setContentSize(NSSize(width: 1280, height: 800))
                window.center()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in
                let commandURL = directory.appendingPathComponent("command.json")
                if let data = try? Data(contentsOf: commandURL),
                   let command = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   let id = command["id"], id != lastID {
                    lastID = id
                    switch command["action"] {
                    case "add-repo", "add-folder":
                        importingModel = true; modelImportError = ""
                        Task { @MainActor in
                            defer { importingModel = false }
                            do {
                                try await store.addLocalModel(
                                    repository: command["action"] == "add-repo" ? command["value"] : nil,
                                    folder: command["action"] == "add-folder" ? URL(fileURLWithPath: command["value"] ?? "") : nil)
                            } catch { modelImportError = error.localizedDescription }
                        }
                    case "add-files":
                        store.showQuickOpen = false; store.showPalette = false
                        store.pane = .ask
                        store.addToDrop((command["value"] ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) })
                    case "pause-files": store.pauseFiling(command["value"] == "true")
                    case "download-audio":
                        if let model = TranscriptionModel(rawValue: command["value"] ?? "") { AudioModels.shared.start(model) }
                    case "transcription-settings":
                        settings?.close()
                        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
                        window.title = "Settings"; window.isReleasedWhenClosed = false
                        window.contentView = NSHostingView(rootView: ScrollView { TranscriptionSettings().environmentObject(store) })
                        settings = window; window.center(); window.makeKeyAndOrderFront(nil)
                    case "select-model": store.selectMLX(command["value"] ?? "")
                    case "download-model": store.downloadRepo(command["value"] ?? "")
                    case "remove-model":
                        if let model = store.customLocalModels.first(where: { $0.id == command["value"] }) { store.removeLocalModel(model) }
                    case "models", "add-model-form":
                        modelWindow?.close()
                        let adding = command["action"] == "add-model-form"
                        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
                        window.title = "Models"; window.isReleasedWhenClosed = false
                        window.contentView = NSHostingView(rootView: Group {
                            if adding { AddLocalModelView().environmentObject(store) }
                            else { LocalModelBrowser().environmentObject(store) }
                        })
                        modelWindow = window; window.center(); window.makeKeyAndOrderFront(nil)
                    case "pane":
                        store.showQuickOpen = false; store.showPalette = false
                        settings?.orderOut(nil)
                        modelWindow?.orderOut(nil)
                        store.tabs = []; store.activeTab = nil
                        store.pane = Pane(rawValue: command["value"] ?? "Library")
                    case "open":
                        if let note = store.notes.first(where: { $0.title == command["value"] }) { store.openNote(note) }
                    case "ask":
                        store.tabs = []; store.activeTab = nil
                        store.newQuestion(); store.pane = .ask
                        store.question = command["value"] ?? ""
                        store.runAsk()
                    case "source": store.openSource(1)
                    case "approve":
                        if let note = store.inboxItems.first { store.approveItem(note) }
                    case "undo":
                        if let record = store.filings.first { store.undoFiling(record) }
                    case "history":
                        if let entry = store.history.first(where: { $0.question == command["value"] }) { store.openHistory(entry) }
                    case "settings":
                        if settings == nil {
                            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
                            window.title = "Settings"
                            window.isReleasedWhenClosed = false
                            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(store))
                            settings = window
                        }
                        settings?.center(); settings?.makeKeyAndOrderFront(nil)
                    default: break
                    }
                }
                let windows = NSApp.windows.filter { $0.isVisible }.map { window in
                    ["title": window.title, "id": window.windowNumber] as [String: Any]
                }
                let state: [String: Any] = [
                    "command": lastID, "busy": store.busy ?? "", "asking": store.asking,
                    "error": store.error ?? "", "answer": store.answer,
                    "question": store.askedQuestion, "sources": store.sources.map { $0.title },
                    "inboxCount": store.inboxItems.count, "filingCount": store.filings.count,
                    "noteTitles": store.notes.map { $0.title }, "windows": windows,
                    "importingModel": importingModel, "modelImportError": modelImportError,
                    "modelDownloads": store.downloads.mapValues { $0.summary }, "modelDownloadErrors": store.downloadErrors,
                    "audioDownloads": AudioModels.shared.progress.mapValues { $0.summary },
                    "audioErrors": AudioModels.shared.errors,
                    "audioAvailable": Array(AudioModels.shared.available),
                    "fileActivity": store.fileActivity.map { ["name": $0.name, "detail": $0.detail, "finished": $0.finished] as [String: Any] },
                    "selectedModel": store.mlxRepo,
                    "customModels": store.customLocalModels.map { ["id": $0.id, "name": $0.name, "source": $0.source.rawValue] },
                ]
                if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: directory.appendingPathComponent("status.json"), options: .atomic)
                }
            }
        }
    }
}
#endif
