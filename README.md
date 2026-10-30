# rules_loki

Hermetic [Grafana Loki](https://grafana.com/oss/loki/) install for Bazel
test compositions. The first rule set in this family that's a pure
glue layer over [`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl) —
`loki_install` is a macro that emits a `kubectl_apply` target
pre-configured with Loki's pinned manifest, namespace, and rollout wait.

```python
load("@rules_loki//:defs.bzl", "loki_install", "loki_health_check")

loki_install(name = "loki_install_bin")
loki_health_check(name = "loki_health_bin")
```

That's the whole API. Drop into `rules_itest` like any other operator
install — see [the smoke test](tests/) for the canonical composition.

**Pinned versions:** Loki helm chart 7.0.0 (Loki appVersion 3.6.7).
Rendered with `deploymentMode: SingleBinary` + `loki.storage.type: filesystem` —
one StatefulSet, no object-storage dependency, auth disabled. The
values file used at render time is exported as
`@rules_loki//config:loki-values.yaml` for inspection / extension.

**Supported platforms (v0.1):** any platform where `bash + python3 + kubectl`
runs (the rules_kubectl substrate). Validated on Linux x86\_64 in CI.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Composition with rules_itest](#composition-with-rules_itest)
- [Macros](#macros)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Contributing](#contributing)

---

## Installation

```python
bazel_dep(name = "rules_loki", version = "0.1.0")
```

That's it — `rules_loki` transitively pulls in
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl),
which is what `loki_install` actually expands to. No extension wiring
required at the consumer level. Bzlmod-only in v0.1; until BCR, consume
via `archive_override` or a git pin.

---

## Quickstart

```python
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_loki//:defs.bzl", "loki_install", "loki_health_check")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# 1. Cluster.
kind_cluster(name = "cluster", k8s_version = "1.35")
kind_health_check(name = "cluster_health", cluster = ":cluster")
itest_service(name = "kind_svc", exe = ":cluster", health_check = ":cluster_health")

# 2. Loki — applies the pinned manifest, waits for sts/loki rollout, idles.
loki_install(name = "loki_install_bin")
loki_health_check(name = "loki_health_bin")

# 3. Wrappers (source the kind env file so KUBECONFIG/KUBECTL cross
#    `exec`). The shape is identical to every other operator rule.
sh_binary(name = "loki_install_wrapper",  srcs = ["install_wrapper.sh"],  data = [":loki_install_bin"])
sh_binary(name = "loki_health_wrapper",   srcs = ["health_wrapper.sh"],   data = [":loki_health_bin"])

itest_service(
    name = "loki_svc",
    exe = ":loki_install_wrapper",
    deps = [":kind_svc"],
    health_check = ":loki_health_wrapper",
)
```

---

## Composition with rules_itest

Stack `loki_svc` underneath any service that needs Loki to exist:

```python
itest_service(name = "myapp_svc",
              exe = ":myapp_install_wrapper",
              deps = [":loki_svc"],          # waits for Loki health before starting
              health_check = ":myapp_health_wrapper")

service_test(services = [":myapp_svc"], test = ":my_assertion_test")
```

The in-tree smoke test does exactly this:
**`kind_svc → loki_svc → curl-pod assertion`**, where the assertion
POSTs a synthetic log to `/loki/api/v1/push` and queries it back via
`/loki/api/v1/query_range` to prove the round-trip.

---

## Macros

### `loki_install(name, namespace = "loki", wait_timeout = "300s", **kwargs)`

Expands to a `kubectl_apply(...)` target that:

- Applies `@rules_loki//private/manifests:loki.yaml` (the pinned, pre-rendered manifest).
- `create_namespace = True` for `namespace` (default `loki`).
- `server_side = True`.
- `wait_for_rollouts = ["sts/loki"]` (the SingleBinary StatefulSet).
- Forwards everything else (e.g. `tags`, `kubeconfig_env`, extra `wait_for_*` lists if you've added sidecar workloads).

Drops into `itest_service.exe`.

### `loki_health_check(name, namespace = "loki", **kwargs)`

Expands to a `kubectl_apply_health_check(...)` target with the matching
wait shape. Drops into `itest_service.health_check`.

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| Loki manifest | Fully hermetic. Pre-rendered by `tools/render_loki.sh` from the upstream chart .tgz, sha-pinned in `tools/versions.bzl`. Committed at `private/manifests/loki.yaml`. | Re-render with `bash tools/render_loki.sh <ver>` (uses `rules_helm`'s helm; no host helm needed). |
| `kubectl` | **Not vendored** — inherited from `rules_kubectl`. Resolves `$KUBECTL` env > PATH > fail. | Cluster providers like `rules_kind` already export a matched `$KUBECTL`. |
| Target cluster | Out of scope — bring your own. | |
| Loki container images | **Pulled at runtime** by the cluster's nodes (Loki, plus `loki-init` initContainer). Not pre-loaded. | Future: `kind_cluster.images` if needed. |
| Smoke-test curl image | `curlimages/curl` pulled at smoke time. | `requires-network`-tagged. |

---

## Contributing

PRs welcome. Conventions match the sibling rule sets:

- New rules need an analysis test in `tests/analysis_tests.bzl`.
- Bumping the pinned chart version: edit `tools/versions.bzl`, add the new `helm_template + sh_binary` block in `tools/BUILD.bazel`, run `bash tools/render_loki.sh <new-version>`, commit.
- `MODULE.bazel.lock` is intentionally not committed.

### Help wanted: macOS validation

The macros are platform-independent (everything runs through `rules_kubectl`'s bash + python3 launcher). A pasted log from a green `bazel test //tests:smoke_test` on macOS would unblock the macOS support claim.
