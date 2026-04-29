"""Maintainer-side: chart .tgz pin for the helm-template render.

Consumers don't see this — it's loaded only by the dev-only chart-fetch
extension under tools/. The committed manifest at
`//private/manifests:loki.yaml` is what consumers actually consume.

Update flow:
    1. Edit LOKI_CHART_VERSIONS to add/change the entry, including
       chart_url + chart_sha256. Compute the chart sha:
           curl -fsSL "<url>" | sha256sum
    2. Add (or update) a `helm_template` + `sh_binary` block in
       tools/BUILD.bazel for the new version.
    3. `bash tools/render_loki.sh <version>` (thin shim around
       `bazel run //tools:render_writeback_<dotted_version>`).
"""

LOKI_CHART_VERSIONS = {
    "7.0.0": {
        # Resolves via the Grafana helm chart repo index at
        # https://grafana.github.io/helm-charts/index.yaml
        "chart_url":    "https://github.com/grafana/helm-charts/releases/download/helm-loki-7.0.0/loki-7.0.0.tgz",
        "chart_sha256": "5eaa28e3535069de2a7ac1f7087ff558e5b4b4a24f0e158072a97e2391132f81",
    },
}
