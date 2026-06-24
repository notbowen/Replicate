import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ReplicateAppModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $model.selectedJobID) {
                    ForEach(model.jobs) { job in
                        JobListRow(job: job)
                            .tag(job.id)
                    }
                }

                Divider()

                HStack {
                    Button {
                        model.addJob()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }

                    Button {
                        model.deleteSelectedJob()
                    } label: {
                        Label("Remove", systemImage: "minus")
                    }
                    .disabled(model.selectedJobID == nil)

                    Spacer()
                }
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let selectedJobBinding {
                JobDetailView(job: selectedJobBinding)
            } else {
                ContentUnavailableView(
                    "No Sync Job Selected",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .onAppear {
            model.refreshPendingItems()
            model.jobsDidChange()
        }
        .onChange(of: model.jobs) { _, _ in
            model.jobsDidChange()
        }
    }

    private var selectedJobBinding: Binding<SyncJob>? {
        guard
            let selectedJobID = model.selectedJobID,
            let index = model.jobs.firstIndex(where: { $0.id == selectedJobID })
        else {
            return nil
        }

        return $model.jobs[index]
    }
}

private struct JobListRow: View {
    let job: SyncJob

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: job.watchEnabled ? "eye" : "folder")
                .foregroundStyle(job.isEnabled ? .primary : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .lineLimit(1)

                Text(job.sourceDisplayPath.isEmpty ? "No source selected" : job.sourceDisplayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if job.lastErrorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct JobDetailView: View {
    @EnvironmentObject private var model: ReplicateAppModel
    @Binding var job: SyncJob

    private var jobPendingItems: [PendingItem] {
        model.pendingItems.filter { $0.jobID == job.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                TextField("Job Name", text: $job.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)

                Toggle("Enabled", isOn: $job.isEnabled)
                    .toggleStyle(.switch)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                folderRow(
                    title: "Source",
                    path: job.sourceDisplayPath,
                    systemImage: "folder",
                    action: { model.chooseSourceFolder(for: job.id) }
                )

                folderRow(
                    title: "Destination",
                    path: job.destinationDisplayPath,
                    systemImage: "externaldrive",
                    action: { model.chooseDestinationFolder(for: job.id) }
                )
            }

            HStack(spacing: 18) {
                Toggle("Delete destination extras", isOn: $job.deleteExtraneousFiles)
                Toggle("Watch for changes", isOn: $job.watchEnabled)

                if model.activeWatchCount > 0 {
                    Label("\(model.activeWatchCount) watching", systemImage: "eye.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    model.refreshPendingItems()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshingPendingItems || model.isSyncing)

                Button {
                    model.sync(jobID: job.id)
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSyncing || !job.isConfigured || !job.isEnabled)

                Button {
                    model.stopSync()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!model.isSyncing)

                Spacer()

                ProgressView()
                    .controlSize(.small)
                    .opacity(model.isSyncing || model.isRefreshingPendingItems ? 1 : 0)
            }

            if let message = job.lastErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            } else if let message = model.watchStatusMessage {
                Label(message, systemImage: "eye")
                    .foregroundStyle(.secondary)
            } else if let lastRunDate = job.lastRunDate {
                Label("Last synced \(lastRunDate.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Label("\(jobPendingItems.count) pending", systemImage: "tray.and.arrow.up")
                    .font(.headline)

                Spacer()

                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            PendingItemsTable(items: jobPendingItems)
        }
        .padding(20)
    }

    @ViewBuilder
    private func folderRow(
        title: String,
        path: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        GridRow {
            Label(title, systemImage: systemImage)
                .frame(width: 120, alignment: .leading)

            Text(path.isEmpty ? "No folder selected" : path)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                Label("Choose", systemImage: "folder.badge.plus")
            }
        }
    }
}

private struct PendingItemsTable: View {
    let items: [PendingItem]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Pending Items",
                systemImage: "checkmark.circle"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(items) {
                TableColumn("Operation") { item in
                    Label(item.operation.title, systemImage: item.operation.systemImage)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 130, max: 150)

                TableColumn("Path") { item in
                    Text(item.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ReplicateAppModel())
}
