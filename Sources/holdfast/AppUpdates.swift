import AppKit
import Combine
import Sparkle
import SwiftUI

/// One updater for all windows. Sparkle owns scheduling, preferences and installation.
@MainActor
final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var availableVersion: String?
    @Published private(set) var restartPending = false
    @Published private(set) var unavailableReason: String?
    var restartBlocker: () -> String? = { nil }

    private var controller: SPUStandardUpdaterController?
    private var resumeInstallation: (() -> Void)?
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"

    override init() {
        super.init()
        // CLI, demo and unsigned builds must never contact the production feed or replace themselves.
        guard Bundle.main.object(forInfoDictionaryKey: "HoldfastUpdatesEnabled") as? Bool == true else {
            unavailableReason = "App updates are available in the signed release of Holdfast."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastCheck)
        do { try updater.start() }
        catch { unavailableReason = "Updates could not start: \(error.localizedDescription)" }
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        if let resumeInstallation {
            if let reason = restartBlocker() {
                let alert = NSAlert()
                alert.messageText = "Holdfast is still in use"
                alert.informativeText = reason
                alert.runModal()
                return
            }
            self.resumeInstallation = nil
            restartPending = false
            resumeInstallation()
        } else if canCheck {
            controller?.checkForUpdates(nil)
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Scheduled checks announce themselves in the toolbar; a click opens Sparkle's standard UI.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard restartBlocker() != nil else { return false }
        resumeInstallation = installHandler
        restartPending = true
        return true
    }
}

struct CheckForAppUpdates: View {
    @EnvironmentObject var updates: AppUpdates

    var body: some View {
        Button(updates.restartPending ? "Restart to Update…" : "Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.canCheck && !updates.restartPending)
    }
}

struct AppUpdateButton: View {
    @EnvironmentObject var updates: AppUpdates

    var body: some View {
        if updates.availableVersion != nil || updates.restartPending {
            Button { updates.checkForUpdates() } label: {
                Label(updates.restartPending ? "Restart to update" : "Update available", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(!updates.canCheck && !updates.restartPending)
            .help(updates.availableVersion.map { "Holdfast \($0) is available" } ?? "Restart to finish updating Holdfast")
        }
    }
}

struct AppUpdateSettings: View {
    @EnvironmentObject var updates: AppUpdates

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(title: "App updates", subtitle: "Keep Holdfast up to date. You choose when to install and restart.")
            HStack {
                Text("Installed version").font(Theme.callout)
                Spacer()
                Text(updates.version).foregroundStyle(.secondary)
            }
            if let reason = updates.unavailableReason {
                Text(reason).font(Theme.callout).foregroundStyle(.secondary)
            } else {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updates.automaticallyChecks }, set: { updates.setAutomaticallyChecks($0) }))
                Text("Checks contact GitHub for version information. Your notes are never included. Updates download only when you choose to install.")
                    .font(Theme.caption).foregroundStyle(.secondary)
                if updates.restartPending {
                    Text("Your update is ready. Finish editing, recording or other work, then restart.").font(Theme.callout)
                } else if let version = updates.availableVersion {
                    Label("Holdfast \(version) is available", systemImage: "arrow.down.circle").font(Theme.callout)
                }
                HStack {
                    CheckForAppUpdates()
                    Spacer()
                    if let date = updates.lastCheck {
                        Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(Theme.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Link("Release notes", destination: URL(string: "https://github.com/lawwu/holdfast/releases/latest")!)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}
