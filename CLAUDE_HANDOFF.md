# Claude Code Handoff — DailyTrack

> Last updated: 2026-03-06
> Repo: https://github.com/YOUR_USERNAME/DailyTrack.git
> Branch: master

## Project Summary

DailyTrack is a SwiftUI habit-tracking app for macOS and iOS. Users define daily tasks with numeric or checkbox goals, view completion percentages and weighted daily scores, track streaks, and visualize history with charts and calendar heatmaps. It supports cumulative task types scoped to weekly, monthly, yearly, or lifetime periods. An optional Cloudflare Workers backend provides cross-device sync via a D1 (SQLite) database.

## Current State

- App builds and runs on both macOS and iOS simulator (Xcode 15+, iOS 17 / macOS 14 targets).
- All task types work: daily numeric, daily checkbox, weekly/monthly/yearly cumulative, and lifetime cumulative.
- Cumulative period tasks participate in the daily score using a derived daily target (`benchmark / period_days`).
- Cloudflare Workers sync backend is functional but requires user-specific configuration (D1 database ID, deployment).
- iOS widget displays today's score, streak, and recent score sparkline.
- This is a sanitized public copy — sensitive data (D1 database ID, Apple Developer Team ID) has been replaced with placeholders.
- The repo has not been pushed to a GitHub remote yet. The remote URL is a placeholder (`YOUR_USERNAME`).

## Environment Setup

1. Open `DailyTrack/DailyTrack.xcodeproj` in Xcode 15+.
2. Set a Development Team under Signing & Capabilities (currently blank in the public copy).
3. Build and run (Cmd+R). SwiftData handles schema creation and lightweight migrations automatically.
4. For the sync backend: `cd cloudflare-worker && npm install && npx wrangler deploy`. You must first create a D1 database (`npx wrangler d1 create dailytrack-sync`) and update `wrangler.toml` with the real database ID. Initialize the schema with `npx wrangler d1 execute dailytrack-sync --file=schema.sql`.

## File Structure

```
DailyTrack/
├── DailyTrack.xcodeproj/
├── DailyTrack/
│   ├── DailyTrackApp.swift              # App entry point, SwiftData container, tab navigation
│   ├── Models/
│   │   ├── TaskDefinition.swift         # @Model — task schema (name, benchmark, unit, weight, cumulative, period)
│   │   ├── DailyEntry.swift             # @Model — daily progress entry linked to a task
│   │   └── TaskProgress.swift           # View model combining task + entry for UI display
│   ├── ViewModels/
│   │   ├── DailyViewModel.swift         # Daily view logic: loading, scoring, streaks, period windows
│   │   ├── HistoryViewModel.swift       # History/analytics: calendar data, trend scores, streaks
│   │   └── SettingsViewModel.swift      # Task CRUD, JSON import/export
│   ├── Views/
│   │   ├── DailyView.swift              # Primary tab: today's tasks, score ring, task rows
│   │   ├── HistoryView.swift            # Charts, calendar heatmap, streak display
│   │   └── SettingsView.swift           # Task editor, period picker, import/export
│   ├── Database/
│   │   └── SeedData.swift               # Seeds example tasks + 10 days of historical data on first launch
│   ├── Sync/
│   │   └── SyncManager.swift            # Cloudflare Workers D1 sync (push/pull with conflict resolution)
│   ├── Shared/
│   │   └── AppGroupContainer.swift      # App group container URL for widget data sharing
│   └── Localization/
│       └── Localizable.xcstrings        # English + German string catalog
├── DailyTrackWidget/
│   ├── DailyTrackWidget.swift           # Widget timeline provider: score, streak, sparkline
│   └── ToggleTaskIntent.swift           # App intent for toggling checkbox tasks from widget
cloudflare-worker/
├── src/index.ts                         # Cloudflare Worker: auth, task/entry sync endpoints
├── schema.sql                           # D1 schema definition
├── wrangler.toml                        # Worker config (D1 database ID is a placeholder)
└── package.json
```

## Architecture

- **SwiftData** is the persistence layer. `TaskDefinition` and `DailyEntry` are `@Model` classes. The app uses a shared `ModelContainer` configured in `DailyTrackApp.swift` with an app group container so the widget can read data.
- **MVVM pattern**: Each tab (Daily, History, Settings) has a corresponding `ViewModel` that owns data loading and business logic. Views observe `@Published` properties.
- **Cumulative period system**: Tasks can be scoped to `week`, `month`, `year`, or `nil` (lifetime). The `periodWindow(for:on:)` helper in each view model computes locale-aware period boundaries using `Calendar.dateInterval(of:for:)`. Period-cumulative tasks contribute to the daily score via `scoringRatio = entry.value / (benchmark / periodDays)`.
- **Daily score**: Weighted average of completion ratios across all non-cumulative tasks and period-cumulative tasks. Lifetime cumulative tasks are excluded from daily scoring.
- **Sync**: Optional push/pull to a Cloudflare Workers endpoint backed by D1. Uses `synced_at` timestamps for conflict resolution (last-write-wins). The worker auto-migrates the schema on first request.
- **Widget**: Reads from the shared SwiftData container. Computes score, streak, and recent scores independently (duplicates some view model logic to avoid importing the main app target).

## Recent Changes

This is a fresh public copy created from a private development repo. The initial commit includes:
- Complete cumulative period timelines feature (weekly/monthly/yearly task scoping with daily score participation)
- SwiftData migration fix: `cumulativePeriod` is `String?` (optional) to support lightweight migration from older schemas
- Generic seed data with example tasks covering all task types
- Sanitized credentials and placeholders

## Known Issues

- `periodWindow` helper is duplicated in `DailyViewModel`, `HistoryViewModel`, and `DailyTrackWidget`. Could be extracted to a shared utility.
- The README references a `Sources/` directory structure and `DatabaseManager.swift` that don't match the actual file layout (the app uses SwiftData, not raw SQLite). README needs updating.
- Git remote URL is a placeholder — needs to be set to the actual GitHub repo URL before pushing.
- Widget and main app share some duplicated score/streak computation logic.

## Next Steps

- [ ] Set the actual GitHub remote URL and push the repo
- [ ] Update README.md to reflect current architecture (SwiftData instead of SQLite, sync backend, cumulative periods, widget)
- [ ] Add App Store screenshots or demo GIF to README
- [ ] Consider extracting `periodWindow` into a shared utility to reduce duplication
- [ ] Add unit tests for score calculation and period window logic
