#!/usr/bin/env bash
# tools/render_loki.sh — thin shim around the Bazel-native render flow.
#
# Maintainer flow for adding/updating a Loki chart version:
#   1. Edit tools/versions.bzl::LOKI_CHART_VERSIONS to add/change the
#      entry, including chart_url + chart_sha256. Compute the chart sha:
#          curl -fsSL "<url>" | sha256sum
#   2. Add (or update) a `helm_template` + `sh_binary` block in
#      tools/BUILD.bazel for the new version.
#   3. Run this script:
#          bash tools/render_loki.sh <chart-version>
#
# Host helm is NOT required — the helm binary comes from rules_helm.
set -euo pipefail

VERSION="${1:?usage: tools/render_loki.sh <chart-version>}"
TARGET="//tools:render_writeback_$(echo "$VERSION" | tr '.' '_')"

echo "[render_loki] $TARGET"
exec bazel run "$TARGET"
