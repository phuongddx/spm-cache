# Full CLI Command Reference

Complete reference for all spm-cache commands and options.

## Table of Contents

1. [Commands](#commands)
2. [Global Options](#global-options)
3. [Command-Specific Options](#command-specific-options)

## Commands

| Command | Description |
|---------|-------------|
| `spm-cache` (or `spm-cache use`) | Integrate cache (default command) |
| `spm-cache build [TARGETS]` | Build targets into xcframeworks |
| `spm-cache build --recursive` | Build all targets in dependency graph |
| `spm-cache off [TARGETS]` | Force source mode for targets |
| `spm-cache rollback` | Restore original project state |
| `spm-cache cache list` | List cached packages |
| `spm-cache cache clean [--all] [--dry]` | Clean cache |
| `spm-cache pkg build TARGET` | Build single package to xcframework |
| `spm-cache remote pull [--config=CONFIG]` | Pull cache from remote |
| `spm-cache remote push [--config=CONFIG]` | Push cache to remote |

## Global Options

| Option | Description |
|------|-------------|
| `--sdk=SDK` | SDK to build for: iphonesimulator, iphoneos, or all |
| `--config=CONFIG` | Build configuration: debug or release |
| `--log-dir=DIR` | Directory for log files |
| `--no-merge-slices` | Disable merging framework slices |
| `--no-library-evolution` | Disable Swift library evolution flags |

## Command-Specific Options

### build

| Option | Description |
|------|-------------|
| `--recursive` | Build recursive dependencies |

### pkg build

| Option | Description |
|------|-------------|
| `--out=PATH` | Output directory (default: current dir) |
| `--checksum` | Compute and display checksum |
| `--sdk=SDK` | iphonesimulator, iphoneos, or all (default: all) |
| `--no-library-evolution` | Disable library evolution flags |

### cache clean

| Option | Description |
|------|-------------|
| `--all` | Remove all cached packages |
| `--dry` | Dry run (show what would be removed) |

### remote pull / push

| Option | Description |
|------|-------------|
| `--config=CONFIG` | Build configuration (default: debug) |
