#!/usr/bin/env bash
# tools/writeback.sh — invoked by `bazel run //tools:render_writeback_<ver>`.
# Copies the helm_template-rendered YAML from bazel-bin into the source
# tree at the canonical committed path.
#
# Unlike rules_capsule / rules_cilium, rules_loki commits ONE manifest
# (the one for the pinned chart version) — there's no per-version
# manifest_sha256 to update because no toolchain verifies it. Git is
# the source of truth.
set -euo pipefail

SRC_BAZEL_BIN="${1:?usage: writeback.sh <bazel-bin source> <dest path under workspace>}"
DEST_REL="${2:?missing dest path}"

WORKSPACE="${BUILD_WORKSPACE_DIRECTORY:?BUILD_WORKSPACE_DIRECTORY not set; run via 'bazel run', not 'bazel test'}"

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -d "${0}.runfiles" ]]; then RUNFILES_DIR="${0}.runfiles"
  elif [[ -d "$(dirname "$0").runfiles" ]]; then RUNFILES_DIR="$(dirname "$0").runfiles"
  fi
  export RUNFILES_DIR
fi
RENDERED="${RUNFILES_DIR}/_main/${SRC_BAZEL_BIN}"
[[ -f "$RENDERED" ]] || { echo "writeback: missing rendered YAML at $RENDERED" >&2; exit 1; }

DEST="${WORKSPACE}/${DEST_REL}"
mkdir -p "$(dirname "$DEST")"
cp -f "$RENDERED" "$DEST"

SHA256=$(sha256sum "$DEST" | awk '{print $1}')
LINES=$(wc -l < "$DEST")

echo "writeback: wrote $DEST"
echo "  sha256: $SHA256"
echo "  lines:  $LINES"
