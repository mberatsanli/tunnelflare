# Cloudflared Binary Setup

This document describes how to set up the cloudflared binary for use with Cloudflare Tunnel UI.

## Overview

The application can use cloudflared from multiple locations:

1. **Custom Path** - User-specified path in Settings
2. **App Bundle** - Bundled within the application
3. **Homebrew (ARM)** - `/opt/homebrew/bin/cloudflared`
4. **Homebrew (Intel)** - `/usr/local/bin/cloudflared`

## Option 1: Using System-Installed cloudflared (Recommended for Development)

If you have cloudflared installed via Homebrew, the application will automatically find it:

```bash
# Install cloudflared via Homebrew
brew install cloudflared

# Verify installation
cloudflared --version
```

## Option 2: Bundling cloudflared in the App

For distribution, you may want to bundle cloudflared within the application.

### Steps to Bundle

1. **Download cloudflared**

   Download the appropriate binary for your target architecture:

   ```bash
   # For Apple Silicon (arm64)
   curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64

   # For Intel (amd64)
   curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64
   ```

2. **Make it executable**

   ```bash
   chmod +x cloudflared
   ```

3. **Add to Xcode Project**

   - Create a `Resources` group in your Xcode project if it doesn't exist
   - Drag the `cloudflared` binary into the Resources group
   - In the file inspector, ensure:
     - Target Membership is checked for CloudflareTunnelUI
     - Copy Bundle Resources includes the file

4. **Configure Build Phase**

   Add a "Copy Files" build phase:
   - Destination: Resources
   - Subpath: (leave empty)
   - Copy only when installing: Unchecked
   - Add `cloudflared` to the list

5. **Code Signing**

   The bundled binary may need to be signed. Add a Run Script build phase:

   ```bash
   if [ -f "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/cloudflared" ]; then
       codesign --force --sign "$CODE_SIGN_IDENTITY" \
           "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/cloudflared"
   fi
   ```

### Universal Binary (Optional)

To support both Intel and Apple Silicon Macs:

```bash
# Download both binaries
curl -L -o cloudflared-arm64 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64
curl -L -o cloudflared-amd64 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64

# Create universal binary
lipo -create -output cloudflared cloudflared-arm64 cloudflared-amd64

# Verify
lipo -info cloudflared
# Should output: Architectures in the fat file: cloudflared are: x86_64 arm64
```

## Binary Location Detection

The `CloudflaredLocator` class handles finding the cloudflared binary in this priority order:

```swift
let locator = CloudflaredLocator(customPath: settings.customCloudflaredPath)
if let binaryPath = locator.locateBinary() {
    print("Found cloudflared at: \(binaryPath.path)")
}
```

## Verification

The application verifies the binary before use:

1. **Existence Check** - File exists at the path
2. **Executable Check** - File has execute permissions
3. **Version Check** - Running `cloudflared --version` succeeds

## Troubleshooting

### Binary Not Found

If cloudflared is not found:

1. Install via Homebrew: `brew install cloudflared`
2. Or specify a custom path in Settings > General > Custom cloudflared Path

### Permission Denied

If you get a permission error:

```bash
chmod +x /path/to/cloudflared
```

### macOS Gatekeeper

If macOS blocks the binary:

1. Go to System Preferences > Security & Privacy > General
2. Click "Allow Anyway" for the blocked app
3. Or run: `xattr -d com.apple.quarantine /path/to/cloudflared`

## Version Requirements

- Minimum cloudflared version: 2023.0.0
- Recommended: Latest stable release

## Updates

The bundled binary does not auto-update. For updates:

1. Download the latest release from GitHub
2. Replace the binary in the app bundle
3. Re-sign if necessary

For development, using Homebrew ensures you always have the latest version:

```bash
brew upgrade cloudflared
```
