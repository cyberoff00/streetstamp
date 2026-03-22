# Build Cache Strategy Design

**Goal:** Keep local Xcode and SwiftPM builds fast by treating derived build artifacts as disposable cache, while preserving any intentional build outputs that may still be useful inside the repo.

## Problem

This repo stores many local build directories under `build/`, including dozens of `build/DerivedData*` directories plus `build/SourcePackages` and module cache directories. These are all reproducible caches, but they currently accumulate in the workspace and are only partially ignored by git.

That leads to three problems:

1. Xcode and SwiftPM spend more time scanning and indexing a larger workspace tree.
2. Local cache paths proliferate because many ad hoc commands use different `-derivedDataPath` values.
3. Git status becomes noisier because some generated directories are not ignored.

## Approach Options

### Option A: Ignore everything under `build/`

This is the simplest rule set, but it is too broad for this repo because some commands intentionally write non-cache outputs into `build/`, and blanket ignores would make those harder to inspect.

### Option B: Ignore only reproducible caches and add a targeted cleanup script

This keeps useful `build/` outputs visible while explicitly treating Xcode/SPM caches as disposable. A cleanup script can remove only known-safe cache directories and leave the rest of the workspace untouched.

### Option C: Move all derived data outside the repo

This is the cleanest long-term setup, but it requires changing many existing commands and plans. That is a separate workflow cleanup, not a safe first pass.

## Recommended Design

Use Option B.

Update `.gitignore` so the repo ignores reproducible build cache directories:

- `build/DerivedData*`
- `build/SourcePackages`
- `build/XCBuildData`
- `build/swift-module-cache`
- `build/tmp-home`
- `build/postcard-status-build.*`
- `build/postcard-status-test.*`

Add a script at `scripts/clean-build-cache.sh` that:

- runs from the repo root
- supports a dry-run mode
- prints which cache directories it will remove
- deletes only known-safe reproducible cache paths under `build/`
- leaves other `build/` outputs alone

## Safety Rules

The cleanup script must not remove:

- source files
- docs
- top-level `tmp/`
- any non-cache build output directories not on the allowlist

The script should be idempotent so it is safe to run repeatedly.
