# Deployment Guide

> **Project:** spm-cache
> **Audience:** Developers, CI/CD engineers

## Prerequisites

### Local Development

- **macOS** (required — uses Xcode toolchain)
- **Ruby >= 3.0.0** (check with `ruby --version`)
- **Swift 6.0+** (check with `swift --version`)
- **Xcode** (with command-line tools: `xcode-select --install`)
- **Bundler** (`gem install bundler`)

### CI/CD

- macOS runner (GitHub Actions: `macos-latest`)
- Ruby 3.x pre-installed on macOS runners
- Xcode pre-installed on macOS runners
- AWS CLI (if using S3 remote cache): `pip install awscli`

## Installation

### From RubyGems

```bash
gem install spm-cache
```

This installs the `spm-cache` CLI. The Swift proxy tool is built from source on first run (requires Swift toolchain).

### From Source (Development)

```bash
git clone https://github.com/phuongddx/spm-cache.git
cd spm-cache

# Install Ruby dependencies
make install

# Build Swift proxy tool
make proxy.build

# Verify
bundle exec spm-cache --help
```

### With Bundler

```ruby
# Gemfile
gem "spm-cache", "~> 0.1"
```

```bash
bundle install
bundle exec spm-cache --help
```

## Project Integration

### 1. Configure spm-cache

Create `spm-cache.yml` in your Xcode project root:

```yaml
ignore: []                    # Packages to exclude from caching
ignore_local: false           # Skip local packages
ignore_build_errors: false    # Don't fail on build errors
keep_pkgs_in_project: false   # Keep original package refs alongside proxy
default_sdk: iphonesimulator
```

### 2. Build Dependencies into Cache

```bash
cd /path/to/your/xcode/project

# Build all SPM targets (resolves graph first)
spm-cache build --recursive

# Or build specific targets with multi-slice xcframeworks (sim + device)
spm-cache pkg build Alamofire --sdk=all --out=~/.spm-cache/debug

# Single-slice builds also supported
spm-cache pkg build Alamofire --sdk=iphonesimulator --out=~/.spm-cache/debug
spm-cache pkg build Alamofire --sdk=iphoneos --out=~/.spm-cache/debug
```

### 3. Use Cache

```bash
# Integrate proxy package (default command)
spm-cache

# Build in Xcode — cached deps use binaries, others use source
```

### 4. Rollback

```bash
spm-cache rollback
```

This removes the `spm-cache/` sandbox and restores original project state.

## Remote Cache Setup

### Git Backend

1. Create a dedicated Git repository for cache storage (e.g., `your-org/ios-spm-cache`)
2. Configure in `spm-cache.yml`:

```yaml
remote:
  debug:
    git: git@github.com:your-org/ios-spm-cache.git
  release:
    git: git@github.com:your-org/ios-spm-cache-release.git
```

3. Pull/push:

```bash
spm-cache remote pull --config=debug
spm-cache remote push --config=debug
```

### S3 Backend

1. Create an S3 bucket (e.g., `s3://your-org-spm-cache/`)
2. Create credentials file at `~/.spm-cache/s3.creds.json`:

```json
{
  "access_key_id": "AKIA...",
  "secret_access_key": "..."
}
```

3. Configure in `spm-cache.yml`:

```yaml
remote:
  debug:
    s3:
      uri: "s3://your-org-spm-cache/debug"
      creds: "~/.spm-cache/s3.creds.json"
```

4. Install AWS CLI: `pip install awscli`

5. Pull/push:

```bash
spm-cache remote pull
spm-cache remote push
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build & Cache
on: [push]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install spm-cache
        run: gem install spm-cache

      - name: Pull remote cache
        run: spm-cache remote pull --config=debug
        working-directory: ./YourApp

      - name: Build dependencies into cache
        run: spm-cache build --recursive
        working-directory: ./YourApp

      - name: Use cache
        run: spm-cache
        working-directory: ./YourApp

      - name: Build app
        run: xcodebuild -project YourApp.xcodeproj -scheme YourApp build

      - name: Push updated cache
        run: spm-cache remote push --config=debug
        working-directory: ./YourApp
```

### Cache Strategy

- **CI:** Pull cache → build missed → push cache → build app
- **Local dev:** Pull cache → use cache → build app
- **Release:** Same as CI but with `--config=release`

## Build Swift Proxy Tool

The Swift proxy tool is auto-built on first use. To build manually:

```bash
make proxy.build
# Binary at: tools/spm-cache-proxy/.build/release/spm-cache-proxy
```

The `ProxyExecutable` class looks for the binary at:
1. `tools/spm-cache-proxy/.build/release/spm-cache-proxy` (local dev)
2. Falls back to building from source if not found

## Troubleshooting

### "Swift proxy tool source not found"

The gem expects `tools/spm-cache-proxy/` to exist. If installed from RubyGems, the tool is built during gem install. If from source, ensure you're in the repo root.

### "No .xcodeproj found"

Run `spm-cache` from the directory containing your `.xcodeproj` file.

### Build errors for specific targets

Add them to the ignore list:

```bash
spm-cache off ProblematicTarget
```

Or set `ignore_build_errors: true` in `spm-cache.yml`.

### Cache not hitting

1. Verify xcframeworks exist: `spm-cache cache list`
2. Check `graph.json` status: `cat spm-cache/packages/proxy/graph.json`
3. Ensure module names match between build and use

### "no library for this platform was found"

The xcframework is missing the device (or simulator) slice. Rebuild with `--sdk=all`:

```bash
spm-cache pkg build {target} --sdk=all --out=~/.spm-cache/debug
```

This produces a multi-slice xcframework containing both `ios-arm64-simulator` and `ios-arm64`.

## Directory Layout After Integration

```
your-project/
├── YourApp.xcodeproj
├── spm-cache.yml              # Config
├── spm-cache.lock             # Lockfile (auto-generated)
└── spm-cache/                 # Sandbox (auto-generated, gitignored)
    ├── packages/
    ├── metadata/
    ├── xcconfigs/
    └── cachemap/
        └── index.html         # Open in browser to view graph
```

Add `spm-cache/` to `.gitignore`:

```
spm-cache/
spm-cache.lock
```
