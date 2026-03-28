#!/bin/sh
# Ensure mounted volume dirs are writable by node (uid 1000).
# When the compose file maps host dirs into the container they may be
# owned by root.  We attempt mkdir -p so that at least the leaf
# directories exist; the deploy script is responsible for running
# `chown -R 1000:1000` on the host side before starting the container.
for dir in /app/media /app/data; do
  mkdir -p "$dir" 2>/dev/null || true
done

exec "$@"
