# Contributing to Tunnelflare

First off, thank you for considering contributing to Tunnelflare! 🎉

This document provides guidelines and information about contributing to this project. Please read it before submitting your contribution.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Coding Guidelines](#coding-guidelines)
- [Submitting Changes](#submitting-changes)
- [Reporting Bugs](#reporting-bugs)
- [Requesting Features](#requesting-features)

---

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

---

## Getting Started

### Prerequisites

Before you begin, ensure you have:

- **macOS 14.0** (Sonoma) or later
- **Xcode 15.0** or later
- **Git** for version control
- **cloudflared** installed for testing (`brew install cloudflared`)
- A **Cloudflare account** with Zero Trust access (for testing)

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:

```bash
git clone https://github.com/mberatsanli/tunnelflare.git
cd Tunnelflare
```

3. Add the upstream repository:

```bash
git remote add upstream https://github.com/mberatsanli/tunnelflare.git
```

---

## Development Setup

### Opening the Project

```bash
# Open in Xcode
open Tunnelflare.xcodeproj
```

### Building

1. Select the `Tunnelflare` scheme in Xcode
2. Choose "My Mac" as the destination
3. Press `⌘B` to build or `⌘R` to build and run

### Running Tests

```bash
# Run all tests
⌘U in Xcode

# Or via command line
xcodebuild test -scheme Tunnelflare -destination 'platform=macOS'
```

### Code Signing

For development, you can use your personal team:

1. Open project settings in Xcode
2. Select the Tunnelflare target
3. Under "Signing & Capabilities", select your personal team
4. Xcode will automatically manage signing

---

## Project Structure

```
Tunnelflare/
├── Tunnelflare/
│   ├── App/                    # App entry point and delegates
│   │   ├── TunnelflareApp.swift
│   │   ├── AppDelegate.swift
│   │   └── AppState.swift
│   │
│   ├── Core/                   # Core business logic
│   │   ├── API/               # Cloudflare API client
│   │   │   ├── Endpoints/     # API endpoint definitions
│   │   │   └── Models/        # API response models
│   │   ├── Auth/              # Authentication & Keychain
│   │   ├── Process/           # cloudflared process management
│   │   ├── Logs/              # Log streaming & parsing
│   │   └── Notifications/     # macOS notifications
│   │
│   ├── Features/              # Feature modules (MVVM)
│   │   ├── Dashboard/         # Main dashboard
│   │   ├── MenuBar/           # Menu bar integration
│   │   ├── Settings/          # App settings
│   │   ├── Auth/              # Login UI
│   │   ├── Logs/              # Log viewer
│   │   └── TunnelCreation/    # New tunnel wizard
│   │
│   ├── Shared/                # Shared utilities & components
│   │   ├── Components/        # Reusable SwiftUI views
│   │   ├── Extensions/        # Swift extensions
│   │   └── Utilities/         # Helper classes
│   │
│   └── Resources/             # Assets, Info.plist, etc.
│
└── TunnelflareTests/          # Unit tests
```

### Architecture

Tunnelflare follows the **MVVM** (Model-View-ViewModel) architecture:

- **Models**: Data structures representing API responses and app state
- **Views**: SwiftUI views for the user interface
- **ViewModels**: Business logic and state management using `@Observable`

---

## Coding Guidelines

### Swift Style

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) with some additions:

#### Naming

```swift
// ✅ Good
func fetchTunnels() async throws -> [Tunnel]
var isAuthenticated: Bool
let apiClient: CloudflareAPIClient

// ❌ Bad
func getTunnels() async throws -> [Tunnel]
var authenticated: Bool
let client: CloudflareAPIClient
```

#### Code Organization

Use `// MARK:` comments to organize code:

```swift
// MARK: - Properties

// MARK: - Initialization

// MARK: - Public Methods

// MARK: - Private Methods
```

#### SwiftUI Views

Keep views small and focused:

```swift
// ✅ Good - Extract subviews
struct TunnelListView: View {
    var body: some View {
        List(tunnels) { tunnel in
            TunnelRowView(tunnel: tunnel)
        }
    }
}

// ❌ Bad - Monolithic view
struct TunnelListView: View {
    var body: some View {
        List(tunnels) { tunnel in
            HStack {
                // 100+ lines of code...
            }
        }
    }
}
```

#### Error Handling

Use Swift's error handling:

```swift
// ✅ Good
func authenticate() async throws {
    guard let token = token else {
        throw AuthError.missingToken
    }
    // ...
}

// ❌ Bad
func authenticate() async -> Bool {
    guard let token = token else {
        return false
    }
    // ...
}
```

### Documentation

Document public APIs with doc comments:

```swift
/// Fetches all tunnels for the selected account.
///
/// - Returns: An array of `Tunnel` objects.
/// - Throws: `APIError` if the request fails.
func fetchTunnels() async throws -> [Tunnel]
```

### Commit Messages

Use clear, descriptive commit messages:

```
feat: Add tunnel search functionality
fix: Resolve menu bar icon not updating
docs: Update installation instructions
refactor: Extract API client from view model
test: Add unit tests for TunnelNameValidator
```

Prefix commits with:
- `feat:` – New feature
- `fix:` – Bug fix
- `docs:` – Documentation changes
- `refactor:` – Code refactoring
- `test:` – Adding or updating tests
- `chore:` – Maintenance tasks

---

## Submitting Changes

### Pull Request Process

1. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** following the coding guidelines

3. **Test your changes**:
   - Run the app and verify functionality
   - Run unit tests (`⌘U`)
   - Test on both light and dark mode

4. **Commit your changes** with descriptive messages

5. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Open a Pull Request** against the `main` branch

### Pull Request Guidelines

- Keep PRs focused on a single feature or fix
- Include a clear description of changes
- Add screenshots for UI changes
- Reference related issues (`Fixes #123`)
- Ensure all tests pass
- Update documentation if needed

### Code Review

All submissions require review. We aim to review PRs within a few days. Feedback may include:

- Requested changes to code style
- Suggestions for better approaches
- Questions about implementation details

Please respond to feedback constructively and make requested changes.

---

## Reporting Bugs

### Before Submitting

1. Check if the bug has already been reported
2. Try to reproduce with the latest version
3. Gather relevant information:
   - macOS version
   - Xcode version (if building from source)
   - cloudflared version
   - Steps to reproduce
   - Expected vs actual behavior

### Bug Report Template

When opening an issue, include:

```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce:
1. Go to '...'
2. Click on '...'
3. See error

**Expected behavior**
What you expected to happen.

**Screenshots**
If applicable, add screenshots.

**Environment:**
- macOS version: [e.g., 14.2]
- Tunnelflare version: [e.g., 1.0.0]
- cloudflared version: [e.g., 2024.1.0]

**Additional context**
Any other context about the problem.
```

---

## Requesting Features

We welcome feature requests! Before submitting:

1. Check if the feature has already been requested
2. Consider if it fits the project's scope
3. Think about the implementation approach

### Feature Request Template

```markdown
**Is your feature request related to a problem?**
A clear description of the problem. Ex. I'm frustrated when [...]

**Describe the solution you'd like**
A clear description of what you want to happen.

**Describe alternatives you've considered**
Any alternative solutions or features you've considered.

**Additional context**
Any other context, mockups, or screenshots.
```

---

## Questions?

Feel free to open a [Discussion](https://github.com/mberatsanli/tunnelflare/discussions) for:

- Questions about the codebase
- Ideas you want to discuss before implementing
- Help with your contribution

---

Thank you for contributing! 🙏
