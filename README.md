# DailyTrack

A SwiftUI daily task tracker for macOS and iOS. Track daily goals, view streaks, and visualize your productivity over time.

## Features

- **Daily Task View**: Enter progress on each task, see completion percentage and daily score
- **Flexible Task Types**: Numeric goals (e.g., 4 hours), simple checkboxes, and cumulative tracking
- **Custom Weights**: Assign importance weights to each task for your daily score
- **History & Analytics**: Calendar heatmap, streak tracking, trend charts
- **Localization**: English and German, adapts to device language
- **Local SQLite Database**: All data stored locally on your device
- **JSON Export/Import**: Back up and edit task definitions via JSON config file

## Getting Started

### Prerequisites
- **Xcode 15+** (for iOS 17 / macOS 14 targets)
- macOS Sonoma or later

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Kaczor594/DailyTrack.git
   ```

2. Open the Xcode project:
   ```bash
   cd DailyTrack
   open DailyTrack.xcodeproj
   ```
   If no `.xcodeproj` exists yet, create one from Xcode:
   - Open Xcode → File → New → Project
   - Choose "Multiplatform App"
   - Set product name to "DailyTrack"
   - Point it to the `DailyTrack/` directory containing the source files

3. Build and run (Cmd+R)

### Database Location

SQLite database is stored at:
- **macOS**: `~/Library/Application Support/DailyTrack/dailytrack.db`
- **iOS**: App's Application Support directory

### Task Configuration

Tasks can be configured in-app via Settings, or by editing the JSON file at:
```
~/Library/Application Support/DailyTrack/tasks_config.json
```

## Architecture

```
DailyTrack/
├── DailyTrackApp.swift          # App entry point + tab navigation
├── Sources/
│   ├── Models/
│   │   ├── TaskDefinition.swift # Task schema (name, benchmark, unit, weight, etc.)
│   │   ├── DailyEntry.swift     # Daily progress entry
│   │   └── TaskProgress.swift   # Combined task + entry for UI
│   ├── ViewModels/
│   │   ├── DailyViewModel.swift    # Daily view logic
│   │   ├── HistoryViewModel.swift  # History/analytics logic
│   │   └── SettingsViewModel.swift # Task configuration logic
│   ├── Views/
│   │   ├── DailyView.swift      # Primary: today's tasks
│   │   ├── HistoryView.swift    # Charts, heatmap, streaks
│   │   └── SettingsView.swift   # Task editor + JSON import/export
│   ├── Database/
│   │   ├── DatabaseManager.swift # SQLite operations
│   │   └── SeedData.swift       # Initial task + historical data
│   └── Localization/
│       └── Localizable.xcstrings # English + German translations
```

## Tech Stack

- **SwiftUI** (iOS 17+ / macOS 14+)
- **SQLite3** (via C API, no external dependencies)
- **Swift Charts** (for trend visualizations)
- **String Catalogs** (`.xcstrings` for localization)
