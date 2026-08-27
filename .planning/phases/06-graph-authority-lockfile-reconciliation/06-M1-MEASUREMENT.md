# Phase 6 — M1 Measurement: Reproduction & Falsifiable Attribution

**Measured:** 2026-08-27
**Reference project:** `/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor`
**Git repo root:** `/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app` (the project dir is a
subdirectory — every `git` path below is relative to that root, not to the project dir)
**Measured from:** `spm-cache` @ `gsd/v0.4.0-build-fidelity-release-automation`, ruby 3.2.3 (rbenv)
**Source under measurement:** unmodified. `git diff --name-only HEAD -- lib spec tools` is empty.

Hypotheses under test (06-RESEARCH.md §Q7):

- **H-lock** — the umbrella faithfully reproduced a stale lock; the lock disagreed with the host.
  Reconciliation fixes it.
- **H-wrongfile** — the locator read a different `Package.resolved` than Xcode did, so the lock never
  described the host graph. Reconciliation alone does **not** fix it; the locator must.
- **H-float** — the lock was right and the umbrella's isolated `swift package resolve` floated the
  version. Phase 7 territory.

---

## Step 0 — Resolved-file candidate inventory

### Pre-existing reference-project state, recorded before anything was touched (T-06-11)

`git status --porcelain` (reference project, branch `main`):

```
 M AGENTS.md
 M CLAUDE.md
 M StressMonitor/StressMonitor.xcodeproj/xcshareddata/xcschemes/StressMonitor.xcscheme
?? .agents/  ?? .bg-shell/  ?? .codex/  ?? .cursor/  ?? .gemini/  ?? .gsd/
?? .kiro/  ?? .opencode/  ?? opencode.json  ?? skills-lock.json
```

`git stash list`:

```
stash@{0}: On main: design-system-checkpoint-pre-conversion (39 mods + 26 components + onboarding VM deletions)
```

`spm-cache.lock` was copied to a scratch path before any measurement ran. **The working tree is dirty
and carries a stash, so no branch switch and no build was performed** — see
`### A3 — assumption failed` and `## Step 4`.

### Candidates: every `Package.resolved` under the project root, excluding `*/.build/*`

| # | Path (relative to project dir) | mtime | pins |
|---|---|---|---|
| 1 | `spm-cache/packages/proxy/Package.resolved` | 2026-08-09 23:56 | 8 |
| 2 | `spm-cache/packages/umbrella/Package.resolved` | 2026-08-09 21:46 | 8 |
| 3 | `StressMonitor.xcodeproj/StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | **2026-07-12 13:34** | **8** |
| 4 | `StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | **2026-08-13 17:27** | **17** |

Identities, candidates 1–3 (identical set in all three):
`activityindicatorview, anchoredpopup, chat, giphy-ios-sdk, kingfisher, libwebp-xcode, mediapicker, swiftuicharts`

Identities, candidate 4 (**the file Xcode writes** — canonical host graph):
`abseil-cpp-binary, app-check, appauth-ios, firebase-ios-sdk, google-ads-on-device-conversion-ios-sdk,
googleappmeasurement, googledatatransport, googlesignin-ios, googleutilities, grpc-binary,
gtm-session-fetcher, gtmappauth, interop-ios-for-google-sdks, leveldb, nanopb, promises, swift-protobuf`

### Raw glob ordering (`installer.rb:169`, `diff_detector.rb:153`)

```
Dir.glob(File.join("<ref>/StressMonitor.xcodeproj", "**/Package.resolved"))
  [0] <ref>/StressMonitor.xcodeproj/StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
  [1] <ref>/StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

.find { |f| File.exist?(f) }
  => <ref>/StressMonitor.xcodeproj/StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

**The locator selects candidate 3** — the nested, git-ignored, 2026-07-12 file with 8 pins — not
candidate 4, the 2026-08-13 file with 17 pins that Xcode actually maintains. Cause is byte ordering:
`S` (0x53) sorts before `p` (0x70), so the nested `StressMonitor.xcodeproj/...` path precedes
`project.xcworkspace/...`. Confirms 06-RESEARCH.md Finding A.

---

## Step 1 — Live DiffDetector verdict

`SPMCache::Core::DiffDetector` instantiated against the reference project from this repo
(`bundle exec ruby`, `$LOAD_PATH.unshift "lib"`), branch `main`:

```
find_package_resolved => <ref>/StressMonitor.xcodeproj/StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
summary: Detected: +2 packages (firebase-ios-sdk, GoogleSignIn-iOS). Regenerating proxy package.
added=2  removed=0  updated=0  empty=false
```

The `+2` originate from `merge_project_refs` reading `project.pbxproj` (`diff_detector.rb:145,167-175`),
which declares exactly two `XCRemoteSwiftPackageReference` entries (firebase-ios-sdk, GoogleSignIn-IOS)
— **not** from the resolved graph. The remaining 15 pins of the real host graph are invisible to the
detector, and the 8 phantom packages are **not** reported as removed.

**Branch coverage.** Per D-11 the same reading was to be taken on `feature/spm-cache-integration`. The
reference working tree is dirty and holds a stash, so no checkout was performed; that branch was read
through git objects instead (`git show <rev>:<path>`), which is read-only and sufficient because the
relevant inputs are committed files. See `### A3 — assumption failed`.

---

## Step 2 — Set arithmetic per candidate

Keyed with `DiffDetector#identity_key` / `#normalize_url` (`diff_detector.rb:195-231`), **not** raw URL
strings, so ssh/https and `.git`-suffix variants cannot register as false non-overlap. `|lock| = 8`
throughout (`spm-cache.lock`, mtime 2026-08-09 21:46, untracked by git).

| Candidate | `\|lock\|` | `\|resolved\|` | `\|intersection\|` |
|---|---|---|---|
| 1 `spm-cache/packages/proxy/Package.resolved` | 8 | 8 | **8** |
| 2 `spm-cache/packages/umbrella/Package.resolved` | 8 | 8 | **8** |
| 3 nested `…/StressMonitor.xcodeproj/…` (**picked by locator**) | 8 | 8 | **8** |
| 4 canonical `…/project.xcworkspace/…` (**written by Xcode**) | 8 | 17 | **0** |

Intersection keys for candidates 1–3:
`github.com/exyte/ActivityIndicatorView, github.com/exyte/AnchoredPopup, github.com/exyte/Chat,
github.com/Giphy/giphy-ios-sdk, github.com/onevcat/Kingfisher, github.com/SDWebImage/libwebp-Xcode,
github.com/exyte/MediaPicker, github.com/willdale/SwiftUICharts`

Candidate 4 intersection: **(none)** — the `main`-branch zero-overlap finding, confirmed live (D-12).

The lock overlaps the file the locator picks **perfectly (8/8)** and the file Xcode writes **not at all
(0/17)**. This pair of numbers is what decides between H-lock and H-wrongfile.

---

## Step 3 — Umbrella emission and realization

### Emitted requirements — `spm-cache/packages/umbrella/Package.swift`

```
 8: .package(url: "https://github.com/exyte/ActivityIndicatorView", revision: "36140867802ae4a1d2b11490bcbbefe058001d14"),
 9: .package(url: "https://github.com/exyte/AnchoredPopup.git",     revision: "2fb9d1ac101b86cbcc12a3f8e571648ce4469d18"),
10: .package(url: "https://github.com/exyte/Chat.git",              revision: "2ea8fc57f719d59940cab6551bcd518e2ec6191c"),
11: .package(url: "https://github.com/Giphy/giphy-ios-sdk",         revision: "37f5b1ff6cf8bc4a78c0bc5eb1b814381bac9580"),
12: .package(url: "https://github.com/onevcat/Kingfisher",          revision: "c152c1915f60c51e4afa0752656993ee5b3c63db"),
13: .package(url: "https://github.com/SDWebImage/libwebp-Xcode",    revision: "0d60654eeefd5d7d2bef3835804892c40225e8b2"),
14: .package(url: "https://github.com/exyte/MediaPicker.git",       revision: "ce2eda6300337d1478a78fc033bce8dd9bf4bb2c"),
15: .package(url: "https://github.com/willdale/SwiftUICharts.git",  revision: "c16f47217d1e32900f6b37c322d419945fadae9c"),
```

**All 8 packages are emitted as exact-commit `revision:` pins. Zero are emitted `from:`.** Per
`Lockfile.swift:118-126` (`versionRequirement`), `revision:` wins whenever a revision is held, and per
the rationale at `Lockfile.swift:115-117` a `revision:` pin *has no range to float within*.

### Umbrella resolved pins — `spm-cache/packages/umbrella/Package.resolved` (mtime 2026-08-09 21:46, 8 pins)

```
activityindicatorview   version=nil  revision=36140867802a
anchoredpopup           version=nil  revision=2fb9d1ac101b
chat                    version=nil  revision=2ea8fc57f719
giphy-ios-sdk           version=nil  revision=37f5b1ff6cf8
kingfisher              version=nil  revision=c152c1915f60
libwebp-xcode           version=nil  revision=0d60654eeefd
mediapicker             version=nil  revision=ce2eda630033
swiftuicharts           version=nil  revision=c16f47217d1e
```

### Realization — checkout HEADs actually on disk under `umbrella/.build/checkouts`

These are the sources the compiler read, and they agree with the emitted pins exactly:

```
ActivityIndicatorView  36140867802a  1.2.1
AnchoredPopup          2fb9d1ac101b  1.1.3
Chat                   2ea8fc57f719  3.0.2
giphy-ios-sdk          37f5b1ff6cf8  2.2.16
Kingfisher             c152c1915f60  8.8.1
libwebp-Xcode          0d60654eeefd  1.5.0
MediaPicker            ce2eda630033  3.3.2
SwiftUICharts          c16f47217d1e  2.10.4
```

### The contemporaneous host graph

`spm-cache.lock` was written 2026-08-09 21:46. The canonical (Xcode-written) `Package.resolved` at the
matching commits `0a73df7` / `1b511d1` (both 2026-08-09, on `feature/spm-cache-integration`) held the
same 8 identities at **different** pins:

```
activityindicatorview   1.2.1    36140867802a
anchoredpopup           1.2.1    dfa61fd6e4e4
chat                    (rev)    2ea8fc57f719
giphy-ios-sdk           2.2.16   37f5b1ff6cf8
kingfisher              8.11.0   410984bf301f
libwebp-xcode           1.6.0    2b5256c29ff4
mediapicker             3.4.2    07fa01cdf084
swiftuicharts           (rev)    c16f47217d1e
```

---

## Per-package attribution table

`H` = host pin (Xcode-written canonical file). `L` = `spm-cache.lock` entry. `U` = umbrella
`Package.resolved` pin. Verdicts assigned strictly by the 06-RESEARCH.md §Q7 decision table.

### Group A — the 8 packages spm-cache actually built (H taken at the contemporaneous canonical commit `0a73df7`, 2026-08-09)

| package | H (host pin) | L (lock entry) | U (umbrella resolved) | emitted requirement kind | verdict |
|---|---|---|---|---|---|
| activityindicatorview | 1.2.1 / `36140867802a` | 1.2.1 / `36140867802a` | `36140867802a` | exact commit (`revision:`) | H-wrongfile |
| anchoredpopup | **1.2.1 / `dfa61fd6e4e4`** | **1.1.3 / `2fb9d1ac101b`** | `2fb9d1ac101b` | exact commit (`revision:`) | H-wrongfile |
| chat | (rev) `2ea8fc57f719` | 3.0.2 / `2ea8fc57f719` | `2ea8fc57f719` | exact commit (`revision:`) | H-wrongfile |
| giphy-ios-sdk | 2.2.16 / `37f5b1ff6cf8` | 2.2.16 / `37f5b1ff6cf8` | `37f5b1ff6cf8` | exact commit (`revision:`) | H-wrongfile |
| kingfisher | **8.11.0 / `410984bf301f`** | **8.8.1 / `c152c1915f60`** | `c152c1915f60` | exact commit (`revision:`) | H-wrongfile |
| libwebp-xcode | **1.6.0 / `2b5256c29ff4`** | **1.5.0 / `0d60654eeefd`** | `0d60654eeefd` | exact commit (`revision:`) | H-wrongfile |
| mediapicker | **3.4.2 / `07fa01cdf084`** | **3.3.2 / `ce2eda630033`** | `ce2eda630033` | exact commit (`revision:`) | H-wrongfile |
| swiftuicharts | (rev) `c16f47217d1e` | 2.10.4 / `c16f47217d1e` | `c16f47217d1e` | exact commit (`revision:`) | H-wrongfile |

Bold rows are the **four packages where the built pin is strictly OLDER than the host pin** —
the motivating stale-transitive symptom.

### Group B — the 17 packages of the current host graph (canonical file, 2026-08-13)

Every row has `L` absent and `U` absent: the umbrella never declared any of them, because the locator
reads candidate 3, which contains none of them.

| package | H (host pin) | L (lock entry) | U (umbrella resolved) | emitted requirement kind | verdict |
|---|---|---|---|---|---|
| abseil-cpp-binary | 1.2024072200.0 / `bbe8b69694d7` | absent | absent | not emitted | H-wrongfile |
| app-check | 11.3.1 / `3e33dd27dd4c` | absent | absent | not emitted | H-wrongfile |
| appauth-ios | 2.1.0 / `a7caeda164dc` | absent | absent | not emitted | H-wrongfile |
| firebase-ios-sdk | 11.15.0 / `fdc352fabaf5` | absent | absent | not emitted | H-wrongfile |
| google-ads-on-device-conversion-ios-sdk | 2.3.0 / `a2d0f1f1666d` | absent | absent | not emitted | H-wrongfile |
| googleappmeasurement | 11.15.0 / `45ce435e9406` | absent | absent | not emitted | H-wrongfile |
| googledatatransport | 10.1.1 / `ba3358d3c3db` | absent | absent | not emitted | H-wrongfile |
| googlesignin-ios | 9.2.0 / `08d8dcecafb5` | absent | absent | not emitted | H-wrongfile |
| googleutilities | 8.1.2 / `9f183ae842be` | absent | absent | not emitted | H-wrongfile |
| grpc-binary | 1.69.1 / `75b31c842f66` | absent | absent | not emitted | H-wrongfile |
| gtm-session-fetcher | 3.5.0 / `a2ab612cb980` | absent | absent | not emitted | H-wrongfile |
| gtmappauth | 5.0.0 / `56e0ccf09a6d` | absent | absent | not emitted | H-wrongfile |
| interop-ios-for-google-sdks | 101.0.0 / `040d087ac226` | absent | absent | not emitted | H-wrongfile |
| leveldb | 1.22.5 / `a0bc79961d7b` | absent | absent | not emitted | H-wrongfile |
| nanopb | 2.30910.1 / `3851d94a4189` | absent | absent | not emitted | H-wrongfile |
| promises | 2.4.1 / `f4a19a3c313d` | absent | absent | not emitted | H-wrongfile |
| swift-protobuf | 1.38.1 / `55d7a1cc5666` | absent | absent | not emitted | H-wrongfile |

**Verdict counts:** H-wrongfile **25**, H-lock **0**, H-float **0**, both **0**.

Group B is called out separately in good faith: read literally, `U == L` (both absent) and `L != H`
matches the §Q7 *H-lock* row. That literal reading is rejected, and the reason is falsifiable rather
than stylistic — see falsifier 3 below. A frozen-but-correct lock (H-lock) predicts the lock holds an
*older state of the host's own graph*; the lock instead holds *another file's* graph in full, and the
locator cannot see 15 of these 17 packages at all. Reconciling `version`/`revision` against the file
the locator currently picks adds none of them.

### Falsifiers applied

**1. H-float is refuted outright for all 8 Group-A packages.** Every package is emitted as an exact
`revision:` pin (Step 3, `Package.swift` lines 8-15) and `U == L` byte-for-byte for all 8, so nothing
drifted. Per `Lockfile.swift:115-117` a `revision:` pin has no range to float within. Concretely for
**kingfisher**: emitted `revision: "c152c1915f60…"`, lock entry `c152c1915f60`, umbrella resolved pin
`c152c1915f60`, and the realized checkout HEAD on disk is `c152c1915f60` (tag 8.8.1). A floated resolve
would have produced a *different* revision downstream of the lock; the four values are identical, so
H-float is excluded. The observation that settles it is the identity `U == L` under an exact-commit
emission.

**2. H-lock is refuted for Group A by provenance, not by narrative.** H-lock and H-wrongfile both
predict `L != H`, so the divergence alone cannot separate them. The separating observation is *which
file the lock's contents match*. The lock's 8 entries are identical — every identity, version, and
revision — to candidate 3, the nested 2026-07-12 file (Step 0/Step 2: intersection 8/8). Against the
canonical file at the contemporaneous commit `0a73df7`, four of those eight disagree. Decisive case:
**anchoredpopup** — the lock holds `1.1.3 / 2fb9d1ac101b`, the nested file holds `1.1.3 / 2fb9d1ac101b`,
and the host's own Xcode-written graph on the same day held `1.2.1 / dfa61fd6e4e4`. A stale snapshot of
the canonical file could never contain `1.1.3`, because no committed revision of the canonical file
ever held that pin. The lock therefore did not come from a frozen read of the host graph; it came from
a different file. That is H-wrongfile.

**3. H-lock is refuted for Group B by absence across the whole history.** `git log --all` over the
canonical `Package.resolved` (12 commits, 2026-03-08 → 2026-08-13) shows no revision of it ever
containing the Group-A identities *and* no revision of `spm-cache.lock` ever containing the Group-B
identities. The lock has never held a firebase-graph pin at any version. There is no stale-lock state
to unfreeze, so freezing is not the operative mechanism for Group B — invisibility is.

**4. The wrong-file mechanism is confirmed positively, not only by elimination.** Step 0's glob
ordering shows the selection is deterministic and explains itself: the nested path sorts first, so
`.find { |f| File.exist?(f) }` returns it on every invocation. The nested directory is git-ignored
build junk (`.gitignore:171`), so it is never updated by Xcode and never cleaned — it has been frozen
at 2026-07-12 while the real graph moved twice (2026-08-09, 2026-08-13).

### A3 — assumption failed

Research assumption A3 held that `feature/spm-cache-integration` still contains the ExyteChat/MediaPicker
state (D-11). **It does not, at the branch tip.**

- Branch tip: `a56a90d` (2026-08-10, "docs: add project setup guides").
- `fb8e773` (2026-08-10, "fix(ci): remove unused ExyteChat/SwiftUICharts proxy dependencies") **is an
  ancestor of the tip** (`git merge-base --is-ancestor` → true), and it also removed the canonical
  `Package.resolved` from git tracking.
- At the tip there is **no tracked `Package.resolved`**, and no `XCRemoteSwiftPackageReference` for any
  exyte package. `git grep -i -E 'exyte|mediapicker' feature/spm-cache-integration` matches only prose
  in `README.md`, `docs/`, and `.planning/` — no package declaration.

The ExyteChat/MediaPicker state survives only at ancestor commits `1b511d1` and `0a73df7`
(both 2026-08-09), which is precisely the era `spm-cache.lock` was written (mtime 2026-08-09 21:46).
Those commits supplied the contemporaneous host graph used as `H` in Group A, read through
`git show <rev>:<path>` without any checkout.

**Consequence:** attribution is complete and unblocked — it rests on committed artifacts, not on a
working-tree state. Only the *live release build* half of ROADMAP success criterion 4 is affected;
see `## Step 4`.

---

## Step 4 — Release build reproduction

### Scheme confirmed (A4 holds)

`xcodebuild -list -project StressMonitor.xcodeproj` (read-only, no checkout) reports:

```
Schemes:
    StressMonitor
    StressMonitorWatch Watch App
    StressMonitorWidgetExtension
```

Research assumption A4 holds — the scheme is named `StressMonitor` as assumed. The command the
research method specifies is therefore, verbatim:

```bash
xcodebuild -project /Users/ddphuong/.../StressMonitor/StressMonitor.xcodeproj \
  -scheme StressMonitor -configuration Release \
  -destination 'generic/platform=iOS Simulator' build
```

### Exit status: not run — deliberately

**This command was not executed. Neither reachable variant of it is both probative and
non-destructive, and running the non-probative one would have spent the evidence for nothing.**

| Build target state | Probative for the stale-transitive symptom? | Safe to run? |
|---|---|---|
| Current working tree (`main`, as checked out) | **No** — `XCLocalSwiftPackageReference` is empty, so spm-cache is not wired into the project at all; the graph is the 17-pin firebase graph and no exyte package is present. A green or red build here says nothing about the 8 packages under attribution. | Yes |
| `1b511d1` / `0a73df7` (2026-08-09, exyte state + spm-cache wired) | **Yes** | **No** — two independent blockers, below |

The two blockers on the probative variant:

1. **A3 failed, so the state is only reachable detached.** `feature/spm-cache-integration`'s tip no
   longer holds the exyte state (`fb8e773` removed it and is an ancestor of the tip). Reaching it means
   a detached checkout of `1b511d1`. The reference working tree carries **3 modified tracked files and
   `stash@{0}`** (Step 0), so a checkout there risks the user's uncommitted work in a repository this
   phase does not own. Recorded as out of bounds rather than attempted.
2. **The build would overwrite the very artifacts being measured.** At `1b511d1` spm-cache *is* wired
   in, so a build regenerates `spm-cache.lock`, `umbrella/Package.swift`, and
   `umbrella/Package.resolved` — the three pre-fix artifacts this plan exists to capture. Per the plan
   objective, the read-only half of M1 "is the only chance to observe pre-fix behavior."

Artifact integrity was verified after all measurement: `spm-cache.lock` is byte-identical to the copy
preserved before any command ran, all five artifact mtimes are unchanged from the Step 0 inventory,
and the reference project is still on `main` with its original dirty state intact.

### Per-package linked version vs host pin

The linked version is nonetheless established, from stronger evidence than a build log: the realized
checkout HEADs under `umbrella/.build/checkouts` (Step 3) **are** the sources the compiler read. Each
was verified by `git -C <checkout> rev-parse HEAD` and `describe --tags`. `H` is the contemporaneous
canonical host pin at `0a73df7` (2026-08-09), the same day the lock was written.

| package | linked (realized checkout HEAD) | host pin (H) | relation |
|---|---|---|---|
| ActivityIndicatorView | 1.2.1 / `36140867802a` | 1.2.1 / `36140867802a` | equal |
| **AnchoredPopup** | **1.1.3 / `2fb9d1ac101b`** | **1.2.1 / `dfa61fd6e4e4`** | **OLDER than host** |
| Chat | 3.0.2 / `2ea8fc57f719` | (rev) `2ea8fc57f719` | equal |
| giphy-ios-sdk | 2.2.16 / `37f5b1ff6cf8` | 2.2.16 / `37f5b1ff6cf8` | equal |
| **Kingfisher** | **8.8.1 / `c152c1915f60`** | **8.11.0 / `410984bf301f`** | **OLDER than host** |
| **libwebp-Xcode** | **1.5.0 / `0d60654eeefd`** | **1.6.0 / `2b5256c29ff4`** | **OLDER than host** |
| **MediaPicker** | **3.3.2 / `ce2eda630033`** | **3.4.2 / `07fa01cdf084`** | **OLDER than host** |
| SwiftUICharts | 2.10.4 / `c16f47217d1e` | (rev) `c16f47217d1e` | equal |

The 17 Group-B packages linked nothing through spm-cache — the umbrella never declared them.

### Did the motivating symptom reproduce?

**Yes.** A linked transitive version strictly older than the host pin reproduced for four packages —
AnchoredPopup 1.1.3 vs host 1.2.1, Kingfisher 8.8.1 vs 8.11.0, libwebp-Xcode 1.5.0 vs 1.6.0, and
MediaPicker 3.3.2 vs 3.4.2 — established from realized on-disk checkouts and committed host graphs
rather than from a live `xcodebuild` run, which was withheld for the reasons above.

---

## M1 verdict

**The dominant mechanism is H-wrongfile, and it is the only mechanism observed in the field case.**
The locator's `Dir.glob(...).find` returns a nested, git-ignored, 2026-07-12 `Package.resolved` that has
been frozen since July while the real Xcode-written graph moved twice. Every downstream component then
agreed with each other perfectly — lock, emitted umbrella requirement, umbrella resolved pin, and
realized checkout are byte-identical for all 8 packages — while collectively describing a graph the host
project does not have. Four packages linked strictly older than the host pin; the other 17 packages of
the real graph were never declared at all.

**Per-verdict counts:** H-wrongfile **25** · H-lock **0** · H-float **0** · both **0**.

H-float is excluded by construction, not by weight of evidence: all 8 packages were emitted as exact
`revision:` pins, which per `Lockfile.swift:115-117` have no range to float within, and `U == L` holds
byte-for-byte. H-lock is excluded by provenance: the lock's contents match the wrongly-picked file
exactly (8/8) and the canonical file not at all (0/17), and no committed revision of the canonical file
ever held the pins the lock carries.

**Implication for Phase 7 (D-14): Phase 7 proceeds.** Its target — the `from:` upward-drift mechanism —
was independently reproduced during research (swift-argument-parser 1.2.0 → 1.8.2, exit 0, no warning),
so it is a real defect regardless of M1. But M1 observed **zero** instances of it in the field case, so
the concrete re-scope is:

1. **Phase 7 is demoted from "the fix for the field bug" to "hardening against a mechanism not yet seen
   in the field."** The motivating release-build failure is not a drift bug and Phase 7 would not have
   prevented it. Phase 7 should be sequenced and sized accordingly rather than treated as urgent.
2. **Candidate disambiguation is promoted into Phase 6 / FID-01 as blocking.** This is the load-bearing
   consequence. Reconciling `version`/`revision` from `find_package_resolved`'s current answer writes the
   phantom graph back onto itself, and success criterion 1 ("re-running `DiffDetector` returns an empty
   diff") would then be satisfied by two components agreeing on the wrong file. Reconciliation without
   a locator fix is not merely incomplete — it converts a visible non-empty diff into a false green.
3. **DIAG-01's set-membership requirement is confirmed by measurement.** A version-only check over the
   intersection reports "0 drifted" on a lock that shares zero packages with the host graph.
