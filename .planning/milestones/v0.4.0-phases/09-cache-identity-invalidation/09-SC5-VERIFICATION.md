---
phase: 09-cache-identity-invalidation
status: passed
verified: 2026-08-29T14:24:56Z
score: SC5 empirical check — 1/1 passed (operator-executed runbook)
note: Empirical SC5 runbook report; the phase-wide report is 09-VERIFICATION.md. Frontmatter
  added 2026-08-29 because tooling reads the alphabetically-first *-VERIFICATION.md — without
  it every status surface reported the phase as "missing" verification.
---

# SC5 Verification: DerivedData Staleness on In-Place xcframework Rebuild

**Verifies:** RESEARCH.md Assumption A1 (MEDIUM confidence) and CONTEXT.md decisions D-11
("spm-cache does NOT proactively purge DerivedData") / D-12 (rebuilds land at the SAME cache
output path, in place). ROADMAP.md Phase 9 success criterion 5.

**Question:** After Plan 01's `hit()` provenance check reports a `missed` for one cached package
and spm-cache rebuilds it — writing a genuinely new `xcframework` bundle at the SAME output path
(`~/.spm-cache/<config>/<module>.xcframework`, per D-12) — does the HOST APP's next Xcode build,
run WITHOUT any manual DerivedData clear, actually link the NEW content? Or does Xcode's
incremental build system silently keep serving the previously-linked, now-stale binary because
nothing about the *app project* itself changed?

**Why this needs a human:** requires the real external reference project, a real Xcode GUI/
`xcodebuild` build, and human judgment comparing binary/symbol content across two DerivedData
states. No Xcode GUI or reference-project repository access exists in the autonomous execution
environment.

**Reference project:** `/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor`
(the same 59-70 package project used for Phase 6's M1 reproduction and Phase 7's benchmark).

---

## Reproduction Procedure

All commands below are run from the reference project root:
```bash
cd /Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor
```

### Step 0 — Pick a target package and note its cache location

Pick any ONE currently-cached package with a library product actually linked into the app (e.g.
`Kingfisher`, `AnchoredPopup`, or any other package already present in this project's
`Package.resolved` / `spm-cache.lock`). Record:

- `PKG_IDENTITY` — the package's identity string as it appears in `spm-cache.lock` (`name:` field
  of its `PackageRef` entry) and in the host's `Package.resolved` (`identity` field under `pins`).
- `PKG_MODULE` — the library product/module name (may differ from `PKG_IDENTITY` for
  multi-product packages).
- `CACHE_DIR` — `~/.spm-cache/debug` (or `~/.spm-cache/release` if that's the configuration you
  build; default config is `debug` unless `spm-cache.yml` says otherwise).
- `XCFW_PATH` — `${CACHE_DIR}/${PKG_MODULE}.xcframework`
- `SIDECAR_PATH` — `${CACHE_DIR}/${PKG_MODULE}.xcframework.provenance.json`

### Step 1 — Cold-build the reference project via spm-cache

```bash
bundle exec spm-cache build --config=debug
```
(or the project's normal invocation — see `spm-cache.yml` for the configured default). Confirm at
least `PKG_MODULE` built and cached:
```bash
test -d "$XCFW_PATH" && echo "xcframework present"
cat "$SIDECAR_PATH"   # confirm a provenance sidecar exists with a non-empty "pins" entry for PKG_IDENTITY
```

### Step 2 — Build the HOST APP in Xcode and record a distinguishing marker

Open `StressMonitor.xcodeproj` (or the `.xcworkspace` if one is used) in Xcode and build the app
target for a simulator destination (Product > Build, `Cmd+B`), OR equivalently:
```bash
xcodebuild -project StressMonitor.xcodeproj -scheme StressMonitor \
  -destination 'generic/platform=iOS Simulator' build
```

Once the build succeeds, locate the LINKED copy of `PKG_MODULE.framework` inside the app's
DerivedData (NOT the source cache dir):
```bash
DERIVED_DATA_APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -iname "StressMonitor-*" | head -1)
find "$DERIVED_DATA_APP" -iname "${PKG_MODULE}.framework" -type d | head -1
```

Record ONE of these markers for that linked framework binary (pick whichever is easiest to
diff — mtime is fastest, `otool`/`nm` is stronger evidence):

- **mtime/hash:** `stat -f "%m" "<linked-framework-path>/${PKG_MODULE}"` and/or
  `shasum "<linked-framework-path>/${PKG_MODULE}"`
- **otool -L:** `otool -L "<linked-framework-path>/${PKG_MODULE}"` (compare install names/versions
  if the rebuild bumps anything observable)
- **nm symbol check:** `nm -gU "<linked-framework-path>/${PKG_MODULE}" | shasum` (a full symbol-set
  hash — changes if literally anything about the compiled output differs)

Write down the recorded value as `MARKER_BEFORE`.

### Step 3 — Force spm-cache to report `PKG_IDENTITY` as `missed` and rebuild that ONE package

Trigger Plan 01's `hit()` miss path by deliberately disagreeing the recorded pin. Either of the
two following approaches works; pick whichever is less disruptive to the working tree:

**Option A — hand-edit the provenance sidecar directly (fastest, no lockfile churn):**
```bash
# Back up first
cp "$SIDECAR_PATH" "${SIDECAR_PATH}.bak"
# Edit the "pins" entry for PKG_IDENTITY to any value that disagrees with the host's
# current pin (e.g. prepend "STALE-" to the existing revision/version string), then save.
```

**Option B — bump the host Package.resolved's pin for PKG_IDENTITY:**
Edit `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, find the `pins` entry whose
`identity` is `PKG_IDENTITY`, and change its `revision`/`version` to a different valid value for
that package (a different tag/commit it actually has). This is the more realistic reproduction
(mirrors an actual host-graph pin bump) but requires knowing another valid revision to pin to.

Then rebuild JUST that one package through spm-cache:
```bash
bundle exec spm-cache build "$PKG_MODULE" --config=debug
```

Confirm the rebuild actually happened (not a hit):
```bash
grep -q '"status".*"missed"' ~/.spm-cache/debug/graph.json 2>/dev/null \
  || echo "check graph.json/build output for a rebuild of $PKG_MODULE, not a cache hit"
```

Confirm the xcframework bundle at `$XCFW_PATH` was genuinely recreated (new content, same path,
per D-12):
```bash
stat -f "%m" "$XCFW_PATH"   # mtime should now be newer than Step 1's build
cat "$SIDECAR_PATH"          # pins[PKG_IDENTITY] should now agree with the host's CURRENT pin again
```

### Step 4 — Rebuild the HOST APP in Xcode again, WITHOUT clearing DerivedData

Do NOT run `rm -rf ~/Library/Developer/Xcode/DerivedData/...` or use Xcode's "Clean Build
Folder". Simply rebuild:
```bash
xcodebuild -project StressMonitor.xcodeproj -scheme StressMonitor \
  -destination 'generic/platform=iOS Simulator' build
```
(or `Cmd+B` in Xcode again, same as Step 2, no manual intervention beyond the normal build
command).

### Step 5 — Re-check the SAME marker and compare

```bash
find "$DERIVED_DATA_APP" -iname "${PKG_MODULE}.framework" -type d | head -1
```
Re-run the SAME marker command used in Step 2 against this path and record it as
`MARKER_AFTER`.

Compare `MARKER_BEFORE` vs `MARKER_AFTER`:

- **If they DIFFER** (new mtime/hash/symbol-set) → the app's rebuilt binary reflects the NEW
  xcframework's content. Xcode's incremental build noticed the in-place content change on its
  own. **PASS.**
- **If they are IDENTICAL** → Xcode kept linking the stale, previously-cached content despite the
  xcframework on disk having genuinely changed. **FAIL** — D-11's "no proactive DerivedData
  purge" decision needs revisiting in a follow-up phase.

### Cleanup

Restore any edited files:
```bash
# If Option A was used:
mv "${SIDECAR_PATH}.bak" "$SIDECAR_PATH"
# If Option B was used:
git checkout -- project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```
Rebuild once more via `bundle exec spm-cache build --config=debug` to restore the cache to a
clean, correctly-pinned state before resuming other work on the reference project.

---

## Outcome

<!-- Filled in by the human running this procedure. Do not pre-fill. -->

- [x] PASS — the rebuilt xcframework's new content reached the app binary without a manual
      DerivedData clear.
- [ ] FAIL — the app binary continued to reflect the stale, pre-rebuild content.

**Marker used:**

**MARKER_BEFORE:**

**MARKER_AFTER:**

**Notes:** PASS reported by the operator via `/gsd-verify-work 9` on 2026-08-29T14:24:56Z;
marker values were not separately recorded.
