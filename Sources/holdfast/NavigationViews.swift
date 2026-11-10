import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var listener = Listener.shared
    @AppStorage("libraryPane") private var libraryPane: Pane = .library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMark(size: 32)
                Text("Holdfast").font(.system(size: 19, weight: .semibold)).tracking(-0.5)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 26)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Pane.primaryPanes) { pane in row(pane) }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("RECENT QUESTIONS").font(Theme.caption2.weight(.medium)).tracking(1).foregroundStyle(Theme.secondary)
                        ForEach(Array(store.conversations.prefix(4)), id: \.latest.id) { conversation in
                            Button { store.openHistory(conversation.latest) } label: {
                                Text(conversation.first.question)
                                    .font(Theme.caption).foregroundStyle(Theme.secondary)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .help(conversation.first.question)
                        }
                        Button { store.pane = .history } label: {
                            Label("All conversations", systemImage: "clock.arrow.circlepath")
                                .font(Theme.caption).foregroundStyle(store.pane == .history ? Theme.accent : Theme.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.top, 28)
                }
                .padding(.horizontal, 10)
            }
            VaultCard().padding(14)
        }
        .background(Theme.sidebar)
        .onChange(of: store.pane) { _, pane in
            if let pane, pane.isLibrary { libraryPane = pane }
        }
    }

    private func row(_ pane: Pane) -> some View {
        let selected = (store.pane ?? .ask).primary == pane
        return Button {
            store.pane = pane == .library && libraryPane.isLibrary ? libraryPane : pane
            store.showList = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: pane.icon).font(.system(size: 16, weight: .regular)).frame(width: 20)
                Text(pane.rawValue).font(Theme.callout.weight(.medium))
                Spacer(minLength: 0)
                if pane == .inbox, !store.inboxItems.isEmpty {
                    Text("\(store.inboxItems.count)").font(Theme.caption2.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.selection, in: RoundedRectangle(cornerRadius: 5))
                }
                if pane == .listen, listener.active {
                    Circle().fill(.red).frame(width: 7, height: 7).accessibilityLabel("Listening now")
                }
                if pane == .ask, store.busy != nil, !store.askedQuestion.isEmpty, store.pane != .ask {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .foregroundStyle(selected ? Theme.accent : Theme.ink)
            .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// All the library's existing browsing tools share one navigation destination.
struct LibraryNavigation: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Library").font(Theme.title2)
                Spacer()
                Text("\(store.notes.count) notes").font(Theme.caption).foregroundStyle(Theme.secondary)
            }
            Picker("Library view", selection: Binding(
                get: { store.pane ?? .library }, set: { store.pane = $0 }
            )) {
                ForEach(Pane.libraryViews) { Text($0.libraryLabel).tag($0) }
            }
            .pickerStyle(.segmented).controlSize(.small).labelsHidden()
        }
        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 10)
    }
}

struct PageHeader: View {
    var pane: Pane
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(pane == .inbox ? "A little review. Then it’s yours."
                 : pane == .listen ? "Stay in the conversation."
                 : pane == .history ? "Your conversations" : pane.rawValue)
                .font(Theme.editorial).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !pane.subtitle.isEmpty {
                Text(pane.subtitle).font(Theme.callout).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
