# Phase 11 Deferred Items

## RESOLVED 2026-08-31 — Tap formula cannot boot under Homebrew Ruby ≥ 3.4 (discovered 2026-08-30, plan 11-03 run 2)

- **Out-of-scope discovery** (tap repo `phuongddx/homebrew-spm-cache`, not this repo): the
  installed `spm-cache` formula's wrapper (`(bin/"spm-cache").write`) execs the gem binstub via
  `env ruby` while exporting `GEM_HOME`/`GEM_PATH` to the isolated `libexec/gems`. On any
  current macOS runner (or user machine) whose unversioned Homebrew Ruby is 3.4+, `nkf`/`kconv`
  are bundled gems (promoted out of the default-gem set in Ruby 3.4.0) and invisible under the
  GEM_PATH isolation, so `CFPropertyList` fails `require 'kconv'` and the CLI dies at boot:
  `cannot load such file -- kconv (LoadError)`. On macos-15 (Ruby 3.3-era interpreter) the CLI
  boots and only the pre-intercept `--version` failure remains.
- **Evidence:** run https://github.com/phuongddx/spm-cache/actions/runs/33322245624 (verify-publish
  job log); formula wrapper comment `to suppress Homebrew Ruby's nkf warnings` + its
  `2> >(grep -v "^Ignoring nkf" >&2)` stderr filter show the friction was masked, not fixed.
- **Impact:** does not affect Phase 11's automation conclusions (update-tap green, verify red at
  the version assertion for the documented pre-intercept reason on macos-15). It DOES mean the
  first fully-green verify-publish at the v0.4.0 release requires a tap-side fix in addition to
  the 11-01 intercept being in the tarball.
- **Suggested tap-side fix (operator, one wrapper edit):** exec the keg-only brewed
  `ruby@3.3` explicitly (e.g. `exec "#{Formula["ruby@3.3"].opt_bin}/ruby" "#{libexec}/bin/spm-cache" "$@"`),
  optionally replacing the stderr-suppression hack.
- Not fixed here: tap formula content is out of this repo's scope (11-RESEARCH A2: "formula
  tweak is tap-side (out of repo)"); executor holds no tap-push credential by design (the
  deploy key's private half exists only as the `TAP_DEPLOY_KEY` repo secret).

**✅ RESOLVED 2026-08-31 during /gsd-verify-work 11 (UAT Test 2), operator-authorized:**
the suggested fix was applied verbatim to the tap — `phuongddx/homebrew-spm-cache@5fd0f0d`
(wrapper now `exec "#{Formula["ruby@3.3"].opt_bin}/ruby" "#{libexec/"bin/spm-cache"}"`), the
macos-15 runner pin was reverted here (`7028069`), and run 33350215267 proved it live on the
Ruby-3.4 image: formula install green, no kconv/nkf LoadError, CLI boots to CLAide, verify
fails exactly at the version assertion. Nothing remains on this item.
  status: acknowledged
