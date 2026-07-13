# CI/CD Integration

GitHub Actions workflow for building and sharing spm-cache artifacts.

## Table of Contents

1. [Full CI Workflow](#full-ci-workflow)
2. [CI vs Local Strategy](#ci-vs-local-strategy)

## Full CI Workflow

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

## CI vs Local Strategy

- **CI**: Pull cache → build missed deps → push cache → build app
- **Local dev**: Pull cache → use cache → build app
