# Cloudflare Tunnel UI

A native macOS application for managing Cloudflare Tunnels with an intuitive graphical interface.

## Overview

Cloudflare Tunnel UI provides a native macOS experience for managing Cloudflare Tunnels. It wraps the `cloudflared` CLI tool with a modern SwiftUI interface, offering features like:

- Menu bar integration for quick access to tunnel status
- Dashboard for managing multiple tunnels
- Real-time log streaming and filtering
- Automatic reconnection on tunnel failures
- Native macOS notifications
- Full dark mode support
- VoiceOver accessibility support

## Features

### Menu Bar Integration
- Always-visible status indicator in the macOS menu bar
- Quick tunnel overview showing up to 5 tunnels
- Start/Stop individual tunnels with one click
- Visual status indicator (green/yellow/red) for overall health
- Keyboard shortcut support (Cmd+D for Dashboard, Cmd+Q to Quit)

### Dashboard
- Comprehensive tunnel management interface
- List view with search and filtering
- Tunnel details with connection info and ingress rules
- Create new tunnels with step-by-step wizard
- Start, stop, and restart tunnels locally

### Log Viewer
- Real-time log streaming from running tunnels
- Filter by tunnel, log level (Debug/Info/Warning/Error)
- Full-text search with debounced input
- Auto-scroll with pause/resume
- Export logs to file
- Color-coded log levels for quick scanning
- Efficient rendering with LazyVStack for 10,000+ entries

### Settings
- Launch at login option
- Show/hide dock icon
- Notification preferences (disconnect, reconnect, crash, auth expiry)
- Auto-reconnect with configurable delay
- Custom cloudflared binary path
- Version information

### Notifications
- Tunnel disconnection alerts with "Reconnect Now" action
- Reconnection success notifications
- Crash detection with "Restart" action
- Authentication expiry warnings

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 5.9+ (for building from source)
- Xcode 15.0+ (for building from source)
- `cloudflared` CLI installed

## Installation

### Installing cloudflared

Install via Homebrew (recommended):
```bash
brew install cloudflared
```

Or download from the [official releases](https://github.com/cloudflare/cloudflared/releases).

The application will automatically detect `cloudflared` in:
1. Custom path (if configured in Settings)
2. App bundle resources
3. Homebrew: `/opt/homebrew/bin/cloudflared`
4. System: `/usr/local/bin/cloudflared`

### Building from Source

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd cloudflare-tunnel/CloudflareTunnelUI
   ```

2. Open in Xcode:
   ```bash
   open CloudflareTunnelUI.xcodeproj
   ```

3. Select your development team in Signing & Capabilities

4. Build and run (Cmd+R)

## Architecture

The application follows a clean architecture pattern with MVVM (Model-View-ViewModel) and clear separation of concerns.

### Project Structure

```
CloudflareTunnelUI/
├── App/                      # Application entry point and global state
│   ├── CloudflareTunnelUIApp.swift   # @main entry point
│   ├── AppDelegate.swift             # AppKit delegate for menu bar
│   └── AppState.swift                # Global observable state
├── Core/                     # Business logic and services
│   ├── API/                  # Cloudflare API client
│   │   ├── Endpoints/        # Type-safe endpoint definitions
│   │   └── Models/           # API response models
│   ├── Auth/                 # Authentication
│   │   ├── AuthenticationManager.swift  # API Token auth coordinator
│   │   └── KeychainManager.swift        # Secure credential storage
│   ├── Process/              # Tunnel process management
│   │   ├── ProcessManager.swift
│   │   ├── TunnelRunner.swift
│   │   ├── HealthMonitor.swift
│   │   └── AutoReconnectService.swift
│   ├── Logs/                 # Log parsing and streaming
│   │   ├── LogBuffer.swift
│   │   ├── LogParser.swift
│   │   └── LogStreamManager.swift
│   └── Notifications/        # macOS notifications
│       └── NotificationService.swift
├── Features/                 # Feature modules
│   ├── MenuBar/              # Menu bar popover
│   ├── Dashboard/            # Main tunnel management
│   │   ├── Views/
│   │   └── ViewModels/
│   ├── Logs/                 # Log viewer
│   ├── Settings/             # App preferences
│   ├── Auth/                 # Login and org selection
│   └── TunnelCreation/       # New tunnel wizard
└── Shared/                   # Shared components and utilities
    ├── Components/           # Reusable UI components
    │   ├── StatusIndicator.swift
    │   ├── LoadingView.swift
    │   └── ErrorView.swift
    ├── Extensions/           # Swift extensions
    └── Utilities/            # Constants, logging, settings
        ├── Constants.swift
        ├── Logger.swift
        ├── AppSettings.swift
        ├── AppError.swift
        └── Debouncer.swift
```

### Key Components

- **AppState**: Central observable state container using Swift's `@Observable` macro. Single source of truth for authentication, tunnels, and UI state.

- **ServiceContainer**: Coordinates tunnel processes, health monitoring, and auto-reconnect. Acts as the service layer between UI and process management.

- **CloudflareAPIClient**: Type-safe API client for Cloudflare's REST API with automatic retry and rate limiting.

- **ProcessManager**: Manages multiple `cloudflared` tunnel processes, tracking state and handling lifecycle.

- **LogStreamManager**: Captures and parses output from tunnel processes, maintaining ring buffers for efficient memory usage.

- **NotificationService**: Handles macOS notification center integration with actionable notifications.

### Data Flow

```
User Action → View → ViewModel → Core Services → AppState
                                       ↓
                              External Systems
                           (Cloudflare API, cloudflared)
                                       ↓
                               AppState Updates
                                       ↓
                              SwiftUI View Updates
```

### Technologies

- **SwiftUI**: Primary UI framework with declarative views
- **@Observable**: Modern Swift observation for state management
- **Async/Await**: Structured concurrency throughout
- **Actor Isolation**: Thread-safe services using Swift actors
- **Combine**: Used for specific reactive patterns (debouncing)

## Development

### Prerequisites

- Xcode 15.0 or later
- Swift 5.9 or later
- macOS 14.0 for running

### Running Tests

```bash
# Run all tests
xcodebuild test -project CloudflareTunnelUI.xcodeproj \
  -scheme CloudflareTunnelUI \
  -destination 'platform=macOS'

# Or from Xcode: Cmd+U
```

### Code Style

The codebase follows Swift API Design Guidelines:

- Clear documentation comments for public APIs
- MARK comments for code organization
- Consistent naming conventions
- Accessibility labels on interactive elements
- Dark mode support using semantic colors

### Adding New Features

1. Create feature folder in `Features/`
2. Add Views in `Views/` subdirectory
3. Add ViewModels in `ViewModels/` subdirectory
4. Register navigation in `NavigationDestination` enum
5. Add to Xcode project file
6. Update tests as needed

## Configuration

### API Token Configuration

The app uses Cloudflare API Tokens for authentication. To set up:

1. **Create an API Token in Cloudflare Dashboard:**
   - Go to [https://dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
   - Click "Create Token"
   - Use "Create Custom Token"

2. **Configure Required Permissions:**
   - **Account > Account Settings > Read** - Required to list accounts and verify access
   - **Account > Cloudflare Tunnel > Edit** - Required to manage tunnels (create, update, delete, run)

3. **Enter Token in App:**
   - Launch Cloudflare Tunnel UI
   - Enter your API Token in the login screen
   - Click "Authenticate"

4. **Token Validation and Storage:**
   - The app validates the token by calling the Cloudflare API
   - Valid tokens are stored securely in the macOS Keychain
   - Your session persists across app restarts

### Keychain Storage

Sensitive data is stored in the macOS Keychain with `kSecAttrAccessibleAfterFirstUnlock`:
- Cloudflare API Token
- Tunnel credentials

### User Defaults

Non-sensitive preferences are stored in UserDefaults:
- Window positions and sizes
- UI preferences
- Selected organization
- Auto-reconnect settings

## Accessibility

The application is designed with accessibility in mind:

- All interactive elements have `.accessibilityLabel`
- Contextual hints with `.accessibilityHint`
- VoiceOver navigation support
- Keyboard navigation throughout
- High contrast support via semantic colors

## Troubleshooting

### cloudflared not found

Ensure `cloudflared` is installed and accessible:
```bash
which cloudflared
cloudflared --version
```

Check Settings > Advanced to configure a custom path if needed.

### Authentication Issues

If you encounter authentication problems:

1. **Verify Token Validity:**
   - Go to [Cloudflare Dashboard > API Tokens](https://dash.cloudflare.com/profile/api-tokens)
   - Check that your token is active and not expired

2. **Check Token Permissions:**
   - Ensure your token has the required permissions:
     - Account > Account Settings > Read
     - Account > Cloudflare Tunnel > Edit
   - If permissions are missing, edit the token or create a new one

3. **Create a New Token:**
   - If the token is invalid or compromised, revoke it in the Dashboard
   - Create a new token with the required permissions
   - Log out of the app and log in with the new token

4. **Check Console Logs:**
   - Open Console.app and filter by "com.tunnelflare-ui"
   - Look for authentication-related error messages

### Tunnel Won't Start

1. Check the Logs view for error messages
2. Verify the tunnel configuration in Cloudflare Dashboard
3. Ensure cloudflared has necessary permissions
4. Try running the tunnel from command line to isolate issues:
   ```bash
   cloudflared tunnel run <tunnel-name>
   ```

### High Memory Usage

The log buffer is limited to 10,000 entries and 50MB. If you see high memory usage:
1. Clear logs from the Logs view
2. Reduce log verbosity in tunnel configuration
3. Check for memory leaks in Console.app

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with tests
4. Ensure all tests pass
5. Submit a pull request

### Code Review Guidelines

- All changes require code review
- Include tests for new functionality
- Update documentation as needed
- Follow existing code style and patterns
- Add accessibility labels to new UI elements
- Test with VoiceOver enabled

### Commit Messages

Follow conventional commits format:
- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation changes
- `refactor:` Code refactoring
- `test:` Test additions/changes
- `chore:` Build/tooling changes

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Cloudflare](https://www.cloudflare.com/) for the cloudflared CLI and excellent API
- Apple's SwiftUI team for the framework
- The Swift community for open-source inspiration

## Version History

- **1.0.0** - Initial release
  - Menu bar integration
  - Dashboard with tunnel management
  - Real-time log viewer
  - Tunnel creation wizard
  - Settings and notifications
