#!/bin/sh

set -eu

usage() {
  cat <<'EOF'
Usage: scripts/clean-build-cache.sh [--dry-run] [--help]

Remove reproducible Xcode/SwiftPM cache directories under build/.

Options:
  --dry-run   Show which paths would be removed without deleting them
  --help      Show this help text
EOF
}

dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
build_dir="$repo_root/build"

if [ ! -d "$build_dir" ]; then
  echo "No build directory found at $build_dir"
  exit 0
fi

targets_file=$(mktemp)
trap 'rm -f "$targets_file"' EXIT INT TERM HUP

find "$build_dir" -mindepth 1 -maxdepth 1 -type d \
  \( \
    -name 'DerivedData*' -o \
    -name 'SourcePackages' -o \
    -name 'XCBuildData' -o \
    -name 'swift-module-cache' -o \
    -name 'tmp-home' -o \
    -name 'postcard-status-build.*' -o \
    -name 'postcard-status-test.*' \
  \) \
  | sort > "$targets_file"

if [ ! -s "$targets_file" ]; then
  echo "No build cache directories matched."
  exit 0
fi

mode_label="Removing"
if [ "$dry_run" -eq 1 ]; then
  mode_label="Would remove"
fi

while IFS= read -r path; do
  rel_path=${path#"$repo_root"/}
  echo "$mode_label $rel_path"
  if [ "$dry_run" -eq 0 ]; then
    rm -rf -- "$path"
  fi
done < "$targets_file"
