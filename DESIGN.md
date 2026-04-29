# rules_loki — design decisions

Hermetic [Grafana Loki](https://grafana.com/oss/loki/) install for Bazel
test compositions. Layered on
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl)
and (at maintainer time)
[`rules_helm`](https://github.com/collider-bazel-extensions/rules_helm).

The first rule set in the family that **doesn't open-code its own install
launcher**. `loki_install` and `loki_health_check` are macros that emit
`kubectl_apply` / `kubectl_apply_health_check` targets pre-configured for
Loki. The whole rule set is ~50 lines of glue + a committed pre-rendered
manifest.

Same family as the in-cluster operator rules (`rules_certmanager`,
`rules_capsule`, `rules_cilium`, `rules_argocd`); distinct from the
build-time CLI wrappers (`rules_helm`, `rules_opa`).

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod-only at v0.1.** | Sibling-family precedent |
| 2 | Architecture | **Layered.** Public surface is two macros (`loki_install`, `loki_health_check`) that wrap `kubectl_apply` / `kubectl_apply_health_check` from rules_kubectl. No per-rule launcher.py, no toolchain, no extension at the public layer. | Validates the rules_kubectl + rules_helm composition that earlier operator rule sets pre-dated. |
| 3 | Manifest provisioning | Loki helm chart **pre-rendered** into `private/manifests/loki.yaml` via `rules_helm`'s `helm_template` + a write-back target under `tools/`. Committed. Consumers don't need helm. | rules_capsule / rules_cilium pattern (post the rules_helm refactor). |
| 4 | Render mode | **`deploymentMode: SingleBinary` + `loki.storage.type: filesystem`.** One StatefulSet pod, no object-storage dependency, auth disabled. Smallest viable Loki for tests; real production deployments would override most of `config/loki-values.yaml`. | Loki-specific |
| 5 | Public surface | `loki_install`, `loki_health_check`. **No `LokiInfo` provider** in v0.1 — nothing introspects it yet. Add when a consumer asks. | Layered architecture |
| 6 | Namespace | `loki` (default). Macros pass `create_namespace = True` to the underlying `kubectl_apply` so the install is self-contained — the upstream chart's manifest doesn't include a Namespace. | rules_kubectl-driven |
| 7 | Wait shape | `wait_for_rollouts = ["sts/loki"]` (the SingleBinary StatefulSet). Other deployment modes would need different waits. | Loki-specific |
| 8 | Values exposed publicly | `@rules_loki//config:loki-values.yaml` — consumers can read what flags the committed manifest was rendered with, and copy + extend it for their own renders. | Transparency |
| 9 | rules_kubectl dependency | **Public dep** (not dev). The macros expand to `kubectl_apply` calls in consumer code — that's the load-bearing layering. | Architectural choice |
| 10 | rules_helm dependency | **Dev-only.** Used at maintainer-side render. Consumers consume the committed manifest, never the chart. | Same as rules_capsule / rules_cilium post-refactor |
| 11 | Smoke assertion | **Round-trip a synthetic log** through Loki's HTTP API. An in-cluster curl pod POSTs to `/loki/api/v1/push`, polls `/loki/api/v1/query_range` for the payload, asserts the round-trip. Proves ingester + querier + filesystem storage actually work — not just "pods Running." | Loki-specific |
| 12 | Naming | snake_case rules/macros, `MixedCaseInfo` providers (none in v0.1), `UPPER_SNAKE` constants. | All siblings |
| 13 | Update workflow | `bash tools/render_loki.sh <chart-version>` → thin shim around `bazel run //tools:render_writeback_<dotted_version>`. Hermetic (rules_helm's helm); no host helm needed. | rules_capsule / rules_cilium pattern |

## Loki-specific notes

- The chart has three subcharts (`grafana-agent-operator`, `minio`, `rollout-operator`); they're all disabled in `config/loki-values.yaml`. Filesystem storage means we don't need minio; auth disabled means we don't need a separate auth gateway; SingleBinary means no rollout coordination.
- The chart's `lokiCanary.enabled` lives at the top level in v7.x. `monitoring.lokiCanary.enabled` is silently ignored (the chart re-renders the DaemonSet anyway). The values file pins both forms defensively.
- Loki rejects `/push` requests with timestamps far from "now". The smoke uses `date +%s%N` for the push and a `[now-60s, now+60s]` window for the query.

## v0.1.0 status (planning)

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only) | planned |
| `loki_install` + `loki_health_check` macros | planned |
| Pinned Loki helm chart 7.0.0 (rendered + committed) | planned |
| `config/loki-values.yaml` (exported) | planned |
| Maintainer render flow (`tools/render_loki.sh`) | planned |
| Analysis test | planned |
| In-tree smoke (kind + Loki + log round-trip) | planned |
| End-to-end `bazel test` runtime | planned (validated under CI Docker; macOS pending) |

## Deferred (not v0.1.0)

- **`LokiInfo` provider** — would let downstream rules introspect the install (version, manifest path, namespace). Add when a consumer asks.
- **Other deployment modes** — `SimpleScalable`, `Distributed`. Would need separate render variants and different `wait_for_rollouts` lists. v0.1 ships SingleBinary only.
- **Object-storage backends** — S3/GCS/Azure. Real production. v0.1 uses filesystem.
- **Promtail / Grafana Agent companion** — log shipper. Separate concern; could be `rules_promtail` later.
- **Hermetic kubectl** — same as everywhere else, deferred to the cluster provider.
- **Multi-version chart selection** — `loki_chart.version()` only handles one version at a time. Add when there's a real consumer with a version need.
