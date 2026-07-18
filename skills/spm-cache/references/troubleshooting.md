# Troubleshooting

Common issues and solutions when using spm-cache.

## Table of Contents

1. [No .xcodeproj found](#no-xcodeproj-found)
2. [Swift proxy tool source not found](#swift-proxy-tool-source-not-found)
3. [Cache not hitting (all deps show "missed")](#cache-not-hitting)
4. [Version conflicts on transitive-only packages](#version-conflicts-on-transitive-only-packages)
5. [No library for this platform was found](#no-library-for-this-platform)
6. [Build errors for specific targets](#build-errors-for-specific-targets)
7. [Library evolution issues](#library-evolution-issues)
8. [Resource bundle issues (Bundle.module not found)](#resource-bundle-issues)
9. [Still stuck?](#still-stuck)

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

2. Check graph.json status — each entry has one of 5 statuses, not just `missed`:

```bash
cat spm-cache/packages/proxy/graph.json | grep -A2 missed
```

| Status | Meaning |
|--------|---------|
| `hit` | Using the cached binary — working as intended |
| `missed` | Not yet built — run `spm-cache build` for this target |
| `ignored` | In the `ignore` list or disabled via `spm-cache off` — always source, expected |
| `excluded` | Not in the `cache_only` allowlist (when `cache_only` is set) — always source, expected |
| `plugin` | Build-tool plugin — never cacheable, expected, not an error |

Only `missed` on a package you *expected* to hit is worth investigating
further; `ignored`/`excluded`/`plugin` are normal, intentional states.

3. Ensure module names match between build and use. The name passed to `spm-cache pkg build` must match the SPM target name exactly.

4. Rebuild and re-run:

```bash
spm-cache build --recursive
spm-cache
```

## Version conflicts on transitive-only packages

Error: `swift package resolve` fails with conflicting version requirements on
a package your app never links directly — e.g. `realm-core` pulled in only
via `realm-swift`.

This is auto-resolved since **v0.2.1** (internal umbrella) and **v0.2.2**
(the real proxy package wired into your Xcode project) — spm-cache detects
when a package's products never appear in any target's directly-linked
dependencies and skips independently pinning it, letting the package that
actually consumes it resolve the version instead.

If you're on v0.2.2 or later and still see this conflict, it's a different,
new conflict — not the known-fixed transitive-only case. See
[Still stuck?](#still-stuck).

## No library for this platform

Error: "no library for this platform was found"

The xcframework is missing the device or simulator slice. Rebuild with `--sdk=all`:

```bash
spm-cache pkg build {target} --sdk=all --out=~/.spm-cache/debug
```

## Build errors for specific targets

Exclude the problematic target (supports glob patterns matched against
product name or package identity):

```bash
spm-cache off ProblematicTarget
spm-cache          # re-run to apply
```

Ignored targets are always compiled from source, even when a cached
xcframework exists. `spm-cache build` skips ignored targets with a warning.

Or set `ignore_build_errors: true` in `spm-cache.yml`.

Prefer an allowlist instead? Set `cache_only` in `spm-cache.yml` — when
non-empty it wins outright over `ignore` (which is skipped entirely), and
every package not listed gets status `excluded` (source, skipped by
`spm-cache build` with a warning, same as `ignored`).

## Library evolution issues

If cached frameworks fail to link across Xcode versions, ensure library evolution flags are enabled (they are by default). Check that `--no-library-evolution` is NOT set in CLI flags or spm-cache.yml.

## Resource bundle issues

`Bundle.module` not found in cached framework:

1. Ensure the package was built with resource bundle support
2. Check that `Bundle.module` accessor is in the cached framework
3. Rebuild: `spm-cache pkg build {target} --sdk=all`

## Still stuck?

If none of the above resolves it, use the `skills/spm-cache-issue` skill to
file a diagnosed GitHub issue — it collects environment/config/cache-state
diagnostics automatically and walks through classifying and filing the issue.
