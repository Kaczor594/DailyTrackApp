import SwiftUI
import SwiftData
import Charts

/// History view: browse past days and see trends.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    @State private var viewModel = HistoryViewModel()
    @State private var selectedDate: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stats summary cards
                    StatsCardsView(
                        currentStreak: viewModel.currentStreak,
                        bestStreak: viewModel.bestStreak,
                        averageScore: viewModel.averageScore,
                        totalDays: viewModel.totalDaysTracked
                    )

                    // Period picker
                    Picker(String(localized: "Period"), selection: $viewModel.selectedPeriod) {
                        ForEach(HistoryViewModel.Period.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: viewModel.selectedPeriod) { _, _ in
                        viewModel.loadData(context: modelContext)
                    }

                    // Trend chart
                    TrendChartView(scores: viewModel.dailyScores)
                        .frame(height: 200)
                        .padding(.horizontal)

                    // Calendar heatmap
                    CalendarHeatmapView(
                        data: viewModel.heatmapData(),
                        period: viewModel.selectedPeriod,
                        onDateTap: { date in
                            selectedDate = date
                        }
                    )
                    .padding(.horizontal)

                    // Per-task breakdown (if a date is selected)
                    if let date = selectedDate {
                        TaskBreakdownView(
                            date: date,
                            scores: viewModel.taskScores(for: date)
                        )
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(String(localized: "History"))
            .onAppear {
                viewModel.loadData(context: modelContext)
            }
            .onChange(of: syncManager.syncVersion) { _, _ in
                viewModel.loadData(context: modelContext)
            }
        }
    }
}

// MARK: - Stats Cards

struct StatsCardsView: View {
    let currentStreak: Int
    let bestStreak: Int
    let averageScore: Double
    let totalDays: Int

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(
                title: String(localized: "Current Streak"),
                value: "\(currentStreak)",
                unit: String(localized: "days"),
                icon: "flame.fill",
                color: .orange
            )
            StatCard(
                title: String(localized: "Best Streak"),
                value: "\(bestStreak)",
                unit: String(localized: "days"),
                icon: "trophy.fill",
                color: .yellow
            )
            StatCard(
                title: String(localized: "Average Score"),
                value: "\(Int(averageScore * 100))%",
                unit: "",
                icon: "chart.bar.fill",
                color: .blue
            )
            StatCard(
                title: String(localized: "Days Tracked"),
                value: "\(totalDays)",
                unit: "",
                icon: "calendar",
                color: .green
            )
        }
        .padding(.horizontal)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))

            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Trend Chart

struct TrendChartView: View {
    let scores: [(date: String, score: Double)]

    @State private var selectedDate: Date?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var chartData: [(date: Date, score: Double)] {
        scores.compactMap { item in
            guard let date = dateFormatter.date(from: item.date) else { return nil }
            return (date, item.score)
        }
    }

    var selectedItem: (date: Date, score: Double)? {
        guard let selected = selectedDate else { return nil }
        return chartData.min(by: {
            abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected))
        })
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(String(localized: "Daily Completion"))
                .font(.headline)

            if chartData.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Data Yet"),
                    systemImage: "chart.line.downtrend.xyaxis",
                    description: Text(String(localized: "Start tracking tasks to see trends here."))
                )
                .frame(height: 160)
            } else {
                Chart(chartData, id: \.date) { item in
                    AreaMark(
                        x: .value("Date", item.date),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", item.date),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(20)

                    if let selected = selectedItem, selected.date == item.date {
                        RuleMark(x: .value("Date", selected.date))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .annotation(position: .top, alignment: .center) {
                                VStack(spacing: 4) {
                                    Text(displayFormatter.string(from: selected.date))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(selected.score * 100))%")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                }
                                .padding(8)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXSelection(value: $selectedDate)
            }
        }
    }
}

// MARK: - Calendar Heatmap

struct CalendarHeatmapView: View {
    let data: [String: Double]
    let period: HistoryViewModel.Period
    var onDateTap: (String) -> Void

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var dates: [Date?] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // Sunday = 1
        let end = Date()
        let start = cal.date(byAdding: .day, value: -period.days, to: end)!

        // Pad start to align with Sunday
        let startWeekday = cal.component(.weekday, from: start) // 1=Sun, 7=Sat
        let padCount = startWeekday - 1 // days to pad before start

        var result: [Date?] = Array(repeating: nil, count: padCount)
        var current = start
        while current <= end {
            result.append(current)
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(String(localized: "Calendar"))
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        let dateStr = dateFormatter.string(from: date)
                        let score = data[dateStr]

                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorForScore(score))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(score != nil ? .white : .secondary)
                            }
                            .onTapGesture {
                                onDateTap(dateStr)
                            }
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func colorForScore(_ score: Double?) -> Color {
        guard let s = score else { return Color.gray.opacity(0.1) }
        switch s {
        case 0: return .red.opacity(0.3)
        case 0..<0.4: return .red.opacity(0.6)
        case 0.4..<0.7: return .orange
        case 0.7..<0.9: return .yellow.opacity(0.8)
        default: return .green
        }
    }
}

// MARK: - Task Breakdown

struct TaskBreakdownView: View {
    let date: String
    let scores: [(task: TaskDefinition, value: Double, ratio: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Task Breakdown — \(date)"))
                .font(.headline)

            ForEach(scores, id: \.task.id) { item in
                HStack {
                    Text(item.task.name)
                        .font(.subheadline)

                    Spacer()

                    Text(formatNumber(item.value))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(Int(min(item.ratio, 1.0) * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorForRatio(item.ratio).opacity(0.15))
                        .foregroundStyle(colorForRatio(item.ratio))
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func colorForRatio(_ r: Double) -> Color {
        switch r {
        case 0: return .gray
        case 0..<0.5: return .red
        case 0.5..<1.0: return .orange
        default: return .green
        }
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() { return String(Int(n)) }
        return String(format: "%.1f", n)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [TaskDefinition.self, DailyEntry.self], inMemory: true)
}
