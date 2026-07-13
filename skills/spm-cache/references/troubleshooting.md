# Troubleshooting

Common issues and solutions when using spm-cache.

## Table of Contents

1. [No .xcodeproj found](#no-xcodeproj-found)
2. [Swift proxy tool source not found](#swift-proxy-tool-source-not-found)
3. [Cache not hitting (all deps show "missed")](#cache-not-hitting)
4. [No library for this platform was found](#no-library-for-this-platform)
5. [Build errors for specific targets](#build-errors-for-specific-targets)
6. [Library evolution issues](#library-evolution-issues)
7. [Resource bundle issues (Bundle.module not found)](#resource-bundle-issues)

## No .xcodeproj found

Run `spm-cache` from the directory containing the `.xcodeproj` file:

```bash
cd /path/to/project
ls *.xcodeproj
```

## Swift proxy tool source not found

The gem expects the Swift proxy tool. If installed from RubyGems/Homebrew, it builds during install. If from source:

```bash
make proxy.build
# Binary at: tools/spm-cache-proxy/.build/release/spm-cache-proxy
```

## Cache not hitting

All deps show "missed" even after building:

1. Verify xcframeworks exist:

```bash
spm-cache cache list
ls ~/.spm-cache/debug/
```

2. Check graph.json status:

```bash
cat spm-cache/packages/proxy/graph.json | grep -A2 missed
```

3. Ensure module names match between build and use. The name passed to `spm-cache pkg build` must match the SPM target name exactly.

4. Rebuild and re-run:

```bash
spm-cache build --recursive
spm-cache
```

## No library for this platform

Error: "no library for this platform was found"

The xcframework is missing the device or simulator slice. Rebuild with `--sdk=all`:

```bash
spm-cache pkg build {target} --sdk=all --out=~/.spm-cache/debug
```

## Build errors for specific targets

Exclude the problematic target:

```bash
spm-cache off ProblematicTarget
spm-cache
```

Or set `ignore_build_errors: true` in `spm-cache.yml`.

## Library evolution issues

If cached frameworks fail to link across Xcode versions, ensure library evolution flags are enabled (they are by default). Check that `--no-library-evolution` is NOT set in CLI flags or spm-cache.yml.

## Resource bundle issues

`Bundle.module` not found in cached framework:

1. Ensure the package was built with resource bundle support
2. Check that `Bundle.module` accessor is in the cached framework
3. Rebuild: `spm-cache pkg build {target} --sdk=all`
