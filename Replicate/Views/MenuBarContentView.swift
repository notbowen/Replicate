import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: ReplicateAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            menuHeader

            Divider()

            pendingSection

            Divider()

            Button {
                model.syncAll()
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(model.isSyncing)

            Button {
                model.refreshPendingItems()
            } label: {
                Label("Refresh Pending Items", systemImage: "arrow.clockwise")
            }
            .disabled(model.isSyncing || model.isRefreshingPendingItems)

            Button {
                model.toggleWatchPaused()
            } label: {
                Label(
                    model.isWatchPaused ? "Resume Watch" : "Pause Watch",
                    systemImage: model.isWatchPaused ? "eye" : "eye.slash"
                )
            }

            Button {
                openWindow(id: "main")
                model.openMainWindow()
            } label: {
                Label("Open Replicate", systemImage: "macwindow")
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Replicate", systemImage: "power")
            }
        }
        .onAppear {
            model.refreshPendingItems()
            model.jobsDidChange()
        }
    }

    private var menuHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(model.isSyncing ? "Syncing" : "Replicate", systemImage: model.menuBarSystemImage)
                .font(.headline)

            Text(model.pendingCountText)
                .foregroundStyle(.secondary)

            if let watchStatusMessage = model.watchStatusMessage {
                Text(watchStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if model.pendingItems.isEmpty {
            Label("Up to date", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            ForEach(model.pendingItems.prefix(10)) { item in
                PendingMenuItemRow(item: item)
            }

            if model.pendingItems.count > 10 {
                Text("\(model.pendingItems.count - 10) more...")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PendingMenuItemRow: View {
    let item: PendingItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.path)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.jobName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: item.operation.systemImage)
        }
    }
}
