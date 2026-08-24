# spm-cache-action

A GitHub Action that restores and saves [spm-cache](https://github.com/phuongddx/spm-cache) binary dependencies in CI. It is a **thin wrapper** around the `spm-cache` gem — all real logic stays in the gem, so this action never needs to reimplement caching semantics.

> **Note:** This action source lives in the `spm-cache` repo under `action/` for development convenience. For GitHub `uses:` resolution, publish it to its own repository: `phuongddx/spm-cache-action`.

## Usage

```yaml
jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v5

      - name: Restore spm-cache
        uses: phuongddx/spm-cache-action@v1
        with:
          command: pull
          backend: s3
          backend-url: s3://my-cache-bucket
          config: debug

      - name: Build (uses cached binaries)
        run: xcodebuild ...

      - name: Save updated cache
        uses: phuongddx/spm-cache-action@v1
        with:
          command: push
          backend: s3
          backend-url: s3://my-cache-bucket
          config: debug
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `command` | `pull`, `push`, or `sync` | yes | `pull` |
| `backend` | `git` or `s3` | yes | `git` |
| `backend-url` | Git remote URL or S3 URI | yes | — |
| `branch` | Git remote branch | no | `main` |
| `config` | Build configuration (`debug`/`release`) | no | `debug` |
| `creds` | S3 credentials JSON file path (s3 only) | no | — |


## Caveats

- **Requires an `.xcodeproj` at the repository root.** `spm-cache init` auto-detects in the working directory only, and the init step is tolerant (`|| true`) — nested-project repos (or a missing project) seed nothing while the workflow still shows green.
- **Misconfiguration currently exits green with warnings.** An unsupported or omitted `backend-url` leaves no remote configured; `remote pull`/`push` then warn ("No remote cache configured. Skipping pull/push." / "Configure remote cache in spm-cache.yml to enable.") and exit 0. Check the logs for those warnings instead of trusting the green checkmark — `required: true` on `backend-url` is not enforced by GitHub runners.
- **[ASSUMED] Git-backend pushes need cache-repo credentials.** The default `actions/checkout` token is scoped to the workflow repository; pushing to a separate git cache repo likely requires a PAT or deploy key configured by the user.

## Design

This action is deliberately thin: `setup-ruby` → `gem install spm-cache` → `spm-cache init` (configure backend) → `spm-cache remote pull/push`. No caching logic is duplicated here — the gem owns all storage and proxy-generation logic. This keeps the action maintenance surface minimal and ensures it never drifts from the gem's behavior.
