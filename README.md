# DailyTrack

A SwiftUI daily task tracker for macOS and iOS. Track daily goals, view streaks, and visualize your productivity over time. Sync across devices with your own Cloudflare Worker backend.

## Features

- **Daily Task View**: Enter progress on each task, see completion percentage and daily score
- **Flexible Task Types**: Numeric goals (e.g., 4 hours), simple checkboxes, and cumulative tracking (weekly/monthly/yearly)
- **Custom Weights**: Assign importance weights to each task for your daily score
- **History & Analytics**: Calendar heatmap, streak tracking, trend charts
- **Home Screen Widget**: Interactive widget with task toggles (iOS 18+)
- **Cloud Sync**: Bidirectional sync across devices via your own Cloudflare Worker + D1 database
- **Localization**: English and German, adapts to device language
- **Local-First**: All data stored locally via SwiftData — works fully offline
- **JSON Export/Import**: Back up and edit task definitions via JSON config file

## Getting Started

### Prerequisites

- **Xcode 15+** (for iOS 17 / macOS 14 targets)
- macOS Sonoma or later
- **Apple Developer account** (free account works for simulator; paid $99/year account needed for device deployment and App Groups)
- **Node.js 18+** and **npm** (for the Cloudflare Worker backend)
- **Cloudflare account** (free tier is sufficient — for cloud sync only)

### 1. Clone and Open the Project

```bash
git clone https://github.com/Kaczor594/DailyTrackApp.git
cd DailyTrackApp/DailyTrack
open DailyTrack.xcodeproj
```

### 2. Configure Apple Development Settings

You must update several identifiers to match your own Apple Developer account:

#### Bundle Identifiers

In Xcode, select each target and change the bundle identifier under **Signing & Capabilities**:

| Target | Current Bundle ID | Change to |
|--------|------------------|-----------|
| DailyTrack | `com.kaczor594.DailyTrack` | `com.YOUR_TEAM.DailyTrack` |
| DailyTrackWidget | `com.kaczor594.DailyTrack.DailyTrackWidget` | `com.YOUR_TEAM.DailyTrack.DailyTrackWidget` |

#### App Group Identifier

The app and widget share data via an App Group. You need to update the identifier in **4 places**:

1. **`DailyTrack/Shared/AppGroupContainer.swift`** (line 5):
   ```swift
   static let appGroupIdentifier = "group.com.YOUR_TEAM.DailyTrack"
   ```

2. **`DailyTrack/DailyTrack.entitlements`**:
   ```xml
   <string>group.com.YOUR_TEAM.DailyTrack</string>
   ```

3. **`DailyTrackWidget/DailyTrackWidget.entitlements`**:
   ```xml
   <string>group.com.YOUR_TEAM.DailyTrack</string>
   ```

4. **`DailyTrackWidgetExtension.entitlements`**:
   ```xml
   <string>group.com.YOUR_TEAM.DailyTrack</string>
   ```

#### Code Signing

In Xcode, for each target (DailyTrack and DailyTrackWidget):
1. Go to **Signing & Capabilities**
2. Select your **Team** from the dropdown
3. Ensure **Automatically manage signing** is checked
4. Xcode will generate provisioning profiles automatically

### 3. Build and Run

Press **Cmd+R** in Xcode. The app works fully offline out of the box — cloud sync is optional.

### 4. Deploy the Cloudflare Worker (Optional — for Cross-Device Sync)

The sync backend is a Cloudflare Worker with a D1 SQLite database. Cloudflare's free tier is sufficient.

#### Install Wrangler (Cloudflare CLI)

```bash
cd cloudflare-worker
npm install
```

#### Authenticate with Cloudflare

```bash
npx wrangler login
```

This opens a browser window to authorize Wrangler with your Cloudflare account.

#### Create the D1 Database

```bash
npx wrangler d1 create dailytrack-sync
```

This outputs something like:

```
Created D1 database 'dailytrack-sync'
database_id = "abc123-def456-..."
```

**Copy the `database_id` value** and paste it into `wrangler.toml`:

```toml
database_id = "abc123-def456-..."  # Replace with your actual ID
```

#### Initialize the Database Schema

```bash
npx wrangler d1 execute dailytrack-sync --remote --file=schema.sql
```

#### Generate and Set Your Sync Token

Generate a random token that the app will use to authenticate with your API:

```bash
openssl rand -hex 32
```

Copy the output and set it as a Cloudflare Worker secret:

```bash
npx wrangler secret put SYNC_TOKEN
```

Paste the token when prompted. **Save this token** — you'll enter it in the app's Settings.

#### Deploy

```bash
npx wrangler deploy
```

This outputs your Worker URL, something like:

```
Published dailytrack-api (...)
  https://dailytrack-api.YOUR_SUBDOMAIN.workers.dev
```

#### Configure the App

1. Open DailyTrack on your device
2. Go to **Settings** tab
3. Enter your Worker URL in **API URL** (e.g., `https://dailytrack-api.your-subdomain.workers.dev`)
4. Enter the sync token you generated in **Sync Token**
5. Tap **Sync Now** to test the connection

Repeat on each device you want to sync.

## Architecture

```
DailyTrack/
├── DailyTrackApp.swift              # App entry point + tab navigation
├── Models/
│   ├── TaskDefinition.swift         # Task schema (name, benchmark, unit, weight, etc.)
│   ├── DailyEntry.swift             # Daily progress entry
│   └── TaskProgress.swift           # Combined task + entry for UI
├── ViewModels/
│   ├── DailyViewModel.swift         # Daily view logic
│   ├── HistoryViewModel.swift       # History/analytics logic
│   └── SettingsViewModel.swift      # Task configuration logic
├── Views/
│   ├── DailyView.swift              # Primary: today's tasks
│   ├── HistoryView.swift            # Charts, heatmap, streaks
│   └── SettingsView.swift           # Task editor + JSON import/export + sync config
├── Sync/
│   └── SyncManager.swift            # Bidirectional sync with Cloudflare D1
├── Shared/
│   └── AppGroupContainer.swift      # Shared container for widget data
├── Database/
│   └── SeedData.swift               # Initial task + sample historical data
└── Localization/
    └── Localizable.xcstrings        # English + German translations

DailyTrackWidget/
├── DailyTrackWidget.swift           # Widget UI + timeline provider
└── ToggleTaskIntent.swift           # Widget interactivity (task toggles)

cloudflare-worker/
├── src/index.ts                     # Sync API endpoints
├── schema.sql                       # D1 database schema
├── wrangler.toml                    # Cloudflare Worker config
└── package.json                     # Dependencies
```

## Sync Protocol

The sync system uses a **last-write-wins** strategy with server-assigned timestamps:

- **Push** (`POST /sync`): Client sends modified tasks/entries. Server accepts them if the client's `updated_at` is newer than the server's copy. Server assigns `synced_at` using server time.
- **Pull** (`GET /sync?since=<timestamp>`): Client requests all changes since the last sync, using `synced_at` (server time) to avoid clock drift issues.
- **Reconcile** (`POST /reconcile`): After first sync, client tells the server which task IDs are active. Server marks anything else as deleted.
- **Delete** (`DELETE /tasks/:id` or `/entries/:id`): Soft-deletes records. Deletion is permanent in the sense that deleted records are never resurrected by sync.

## Tech Stack

- **SwiftUI** (iOS 17+ / macOS 14+)
- **SwiftData** (local persistence)
- **Swift Charts** (trend visualizations)
- **WidgetKit** (home screen widget, iOS 18+)
- **Cloudflare Workers** (sync API)
- **Cloudflare D1** (server-side SQLite database)
- **String Catalogs** (`.xcstrings` for localization)

## Troubleshooting

### Sync Issues

- **"Unauthorized" error**: Double-check that the Sync Token in the app matches the secret you set with `wrangler secret put SYNC_TOKEN`. The token is case-sensitive.
- **"Network error" or connection refused**: Verify the API URL in Settings. It should be the full URL including `https://` (e.g., `https://dailytrack-api.your-subdomain.workers.dev`). No trailing slash.
- **Data not appearing on other devices**: Each device must have the same API URL and Sync Token configured. Tap **Sync Now** on each device after setup.

### Build Issues

- **App Group errors**: Make sure the App Group identifier matches across `AppGroupContainer.swift` and all three `.entitlements` files. The identifier must also be registered in your Apple Developer portal if deploying to a physical device.
- **Code signing errors**: Select your development team in Xcode under **Signing & Capabilities** for both the main app and widget targets.
- **Widget not showing data**: The widget and app must share the same App Group identifier. Rebuild both targets after changing it.

## Security Notes

- The Cloudflare Worker uses a **bearer token** for authentication. Anyone with your token and API URL can read/write your data. Treat the sync token like a password.
- The CORS policy is set to `"*"` (permissive) since the API is consumed by a native app, not a browser. If you expose the API to a web frontend, restrict the `Access-Control-Allow-Origin` header to your domain.
- The sync token is stored in UserDefaults on the client. For higher security, consider migrating to iOS Keychain storage.
- All sync data is transmitted over HTTPS.

## License

This project is open source. You are free to fork, modify, and deploy your own instance.
