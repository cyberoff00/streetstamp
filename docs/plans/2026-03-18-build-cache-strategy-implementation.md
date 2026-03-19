# Build Cache Strategy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ignore reproducible Xcode/SwiftPM cache directories and add a safe local cleanup script for them.

**Architecture:** Keep `build/` partially visible because this repo sometimes stores intentional outputs there, but explicitly classify known Xcode and SwiftPM cache directories as disposable. Add a shell script with a dry-run mode so cleanup stays safe and repeatable.

**Tech Stack:** git ignore rules, POSIX shell, Xcode/SwiftPM cache layout

---

### Task 1: Expand ignored cache directories

**Files:**
- Modify: `/.gitignore`

**Step 1: Add ignore rules for reproducible cache directories**

Extend `.gitignore` to cover the build cache paths that should never show up in git status:

- `build/SourcePackages/`
- `build/XCBuildData/`
- `build/swift-module-cache/`
- `build/tmp-home/`
- `build/postcard-status-build.*/`
- `build/postcard-status-test.*/`

Keep the existing `build/DerivedData*` patterns.

**Step 2: Verify the ignore file stays narrowly scoped**

Confirm the new patterns still allow non-cache `build/` outputs to remain visible if they are intentionally created.

### Task 2: Add a targeted cleanup script

**Files:**
- Create: `/scripts/clean-build-cache.sh`

**Step 1: Write the script interface**

Support:

- default execution from the repo root
- `--dry-run` to print targets without deleting
- `--help` for usage text

**Step 2: Implement cache target discovery**

Match only known-safe cache patterns:

- `build/DerivedData*`
- `build/SourcePackages`
- `build/XCBuildData`
- `build/swift-module-cache`
- `build/tmp-home`
- `build/postcard-status-build.*`
- `build/postcard-status-test.*`

**Step 3: Implement deletion**

Print each target and remove it only when not in dry-run mode.

**Step 4: Make the script executable**

Ensure the file has execute permissions.

### Task 3: Verify behavior

**Files:**
- Verify: current repo build cache directories

**Step 1: Run dry-run verification**

Run:

```bash
scripts/clean-build-cache.sh --dry-run
```

Expected:

- exits successfully
- lists only cache directories from the allowlist
- does not list unrelated repo paths

**Step 2: Check git-visible changes**

Run:

```bash
git status --short
```

Expected:

- `.gitignore` and the new script appear
- existing unrelated user changes remain untouched

**Step 3: Summarize safe cleanup policy**

Document which directories are now safe to clean and which `build/` directories remain intentionally unhandled.
