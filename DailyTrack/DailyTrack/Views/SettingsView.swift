import SwiftUI
import SwiftData

/// Settings view for managing task definitions.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.tasks) { task in
                        TaskDefinitionRow(task: task, onToggleActive: {
                            viewModel.toggleActive(task)
                            syncManager.debouncedSync(context: modelContext)
                        })
                        .onTapGesture {
                            viewModel.editingTask = task
                            viewModel.showingEditSheet = true
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deleteTask(viewModel.tasks[index])
                        }
                        syncManager.debouncedSync(context: modelContext)
                    }
                    .onMove { source, destination in
                        viewModel.moveTask(from: source, to: destination)
                        syncManager.debouncedSync(context: modelContext)
                    }
                } header: {
                    Text("Tasks")
                }

                // Cloud Sync section
                Section {
                    @Bindable var sync = syncManager
                    TextField(String(localized: "API URL"), text: $sync.apiURL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    SecureField(String(localized: "Sync Token"), text: $sync.syncToken)

                    HStack {
                        Button {
                            Task {
                                await syncManager.sync(context: modelContext)
                                viewModel.loadTasks(context: modelContext)
                            }
                        } label: {
                            Label(String(localized: "Sync Now"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(syncManager.isSyncing || !syncManager.syncEnabled)

                        Spacer()

                        if syncManager.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let lastSync = syncManager.lastSyncDate {
                        HStack {
                            Text(String(localized: "Last sync"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }

                    if let error = syncManager.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(String(localized: "Cloud Sync"))
                } footer: {
                    Text(String(localized: "Enter your Cloudflare Worker URL and token to sync between devices."))
                        .font(.caption2)
                }

                Section {
                    Button {
                        viewModel.saveConfigFile()
                    } label: {
                        Label(String(localized: "Export Tasks to JSON"), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        viewModel.loadConfigFile()
                    } label: {
                        Label(String(localized: "Import Tasks from JSON"), systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Configuration File")
                } footer: {
                    Text(String(localized: "Tasks are saved at: \(viewModel.configFilePath().path)"))
                        .font(.caption2)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                #endif
            }
            .sheet(isPresented: $viewModel.showingAddSheet) {
                TaskEditorSheet(
                    task: nil,
                    onSave: { task in
                        viewModel.addTask(task)
                        syncManager.debouncedSync(context: modelContext)
                    }
                )
            }
            .sheet(isPresented: $viewModel.showingEditSheet) {
                if let task = viewModel.editingTask {
                    TaskEditorSheet(
                        task: task,
                        onSave: { updated in
                            viewModel.updateTask(updated)
                            syncManager.debouncedSync(context: modelContext)
                        }
                    )
                }
            }
            .onAppear {
                viewModel.loadTasks(context: modelContext)
            }
        }
    }
}

// MARK: - Task Row in Settings

struct TaskDefinitionRow: View {
    let task: TaskDefinition
    var onToggleActive: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.name)
                        .font(.headline)
                        .foregroundStyle(task.isActive ? .primary : .secondary)

                    if task.isCumulative {
                        Text(task.hasPeriod ? {
                            switch task.cumulativePeriod ?? "none" {
                            case "week": return String(localized: "Weekly")
                            case "month": return String(localized: "Monthly")
                            case "year": return String(localized: "Yearly")
                            default: return String(localized: "Cumulative")
                            }
                        }() : String(localized: "Cumulative"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    if task.isCheckbox {
                        Text(String(localized: "Checkbox"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 12) {
                    Label(String(localized: "Goal: \(formatNumber(task.benchmark)) \(task.unit)"), systemImage: "target")
                    Label(String(localized: "Weight: \(formatNumber(task.weight))"), systemImage: "scalemass")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onToggleActive()
            } label: {
                Image(systemName: task.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isActive ? .green : .gray)
            }
            .buttonStyle(.plain)
        }
        .opacity(task.isActive ? 1.0 : 0.6)
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() { return String(Int(n)) }
        return String(format: "%.1f", n)
    }
}

// MARK: - Task Editor Sheet

struct TaskEditorSheet: View {
    let task: TaskDefinition?
    var onSave: (TaskDefinition) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var benchmark: String = "1"
    @State private var unit: String = ""
    @State private var weight: String = "1"
    @State private var isCumulative: Bool = false
    @State private var cumulativePeriod: String = "none"
    @State private var isCheckbox: Bool = false

    var isEditing: Bool { task != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Task Name"), text: $name)

                    TextField(String(localized: "Unit (e.g., hours, pages)"), text: $unit)
                } header: {
                    Text(String(localized: "Task Details"))
                }

                Section {
                    Toggle(String(localized: "Simple Checkbox"), isOn: $isCheckbox)

                    if !isCheckbox {
                        HStack {
                            Text(benchmarkLabel)
                            Spacer()
                            TextField("1", text: $benchmark)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }

                    Toggle(String(localized: "Cumulative (track total over time)"), isOn: $isCumulative)
                        .onChange(of: isCumulative) { _, newValue in
                            if !newValue {
                                cumulativePeriod = "none"
                            }
                        }

                    if isCumulative {
                        Picker(String(localized: "Period"), selection: $cumulativePeriod) {
                            Text(String(localized: "None (lifetime)")).tag("none")
                            Text(String(localized: "Weekly")).tag("week")
                            Text(String(localized: "Monthly")).tag("month")
                            Text(String(localized: "Yearly")).tag("year")
                        }
                    }
                } header: {
                    Text(String(localized: "Tracking"))
                }

                Section {
                    HStack {
                        Text(String(localized: "Weight"))
                        Spacer()
                        TextField("1", text: $weight)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                } header: {
                    Text(String(localized: "Scoring"))
                } footer: {
                    Text(String(localized: "Higher weight means this task counts more toward your daily score."))
                }
            }
            .formStyle(.grouped)
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 450)
            #endif
            .navigationTitle(isEditing ? String(localized: "Edit Task") : String(localized: "New Task"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let t = task {
                    name = t.name
                    benchmark = String(t.benchmark)
                    unit = t.unit
                    weight = String(t.weight)
                    isCumulative = t.isCumulative
                    cumulativePeriod = t.cumulativePeriod ?? "none"
                    isCheckbox = t.isCheckbox
                }
            }
        }
    }

    private var benchmarkLabel: String {
        switch cumulativePeriod {
        case "week": return String(localized: "Weekly Target")
        case "month": return String(localized: "Monthly Target")
        case "year": return String(localized: "Yearly Target")
        default: return String(localized: "Daily Benchmark")
        }
    }

    private func save() {
        let benchVal = Double(benchmark.replacingOccurrences(of: ",", with: ".")) ?? 1.0
        let weightVal = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 1.0

        if let existing = task {
            // Update existing managed object
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.benchmark = benchVal
            existing.unit = unit.trimmingCharacters(in: .whitespaces)
            existing.weight = weightVal
            existing.isCumulative = isCumulative
            existing.cumulativePeriod = cumulativePeriod
            existing.isCheckbox = isCheckbox
            onSave(existing)
        } else {
            let result = TaskDefinition(
                name: name.trimmingCharacters(in: .whitespaces),
                benchmark: benchVal,
                unit: unit.trimmingCharacters(in: .whitespaces),
                weight: weightVal,
                isCumulative: isCumulative,
                cumulativePeriod: cumulativePeriod,
                isCheckbox: isCheckbox
            )
            onSave(result)
        }
        dismiss()
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [TaskDefinition.self, DailyEntry.self], inMemory: true)
}
