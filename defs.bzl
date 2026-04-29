"""Public API for rules_loki.

Two macros that wrap rules_kubectl's `kubectl_apply` /
`kubectl_apply_health_check` with Loki-specific defaults: namespace,
the committed pre-rendered manifest, and the right wait shape (Loki's
SingleBinary deployment is a StatefulSet, not a Deployment).

Consumers compose them into `rules_itest` setup steps the same way they
would any other operator install — see the in-tree smoke test for the
canonical pattern.
"""

load("@rules_kubectl//:defs.bzl", "kubectl_apply", "kubectl_apply_health_check")

# StatefulSet name in the rendered manifest. SingleBinary mode names it
# `loki` (no release-name prefix because Helm omits it for the SingleBinary
# template). Consumers don't need to know this — the macros wire it.
_LOKI_STS = "sts/loki"

def loki_install(
        name,
        namespace = "loki",
        wait_timeout = "300s",
        **kwargs):
    """Apply the pinned Loki manifest into `namespace` and block until the
    SingleBinary StatefulSet has rolled out before idling.

    Drops into `itest_service.exe`.

    Args:
      name: target name.
      namespace: target namespace. Pre-created idempotently. Default
        `loki` matches what the rendered manifest's references expect;
        change at your own risk (you'll need a re-rendered manifest with
        a matching release name).
      wait_timeout: timeout for the `kubectl rollout status` wait.
      **kwargs: forwarded to `kubectl_apply` (e.g. `tags`, `kubeconfig_env`,
        extra `wait_for_*` lists if you've added sidecar workloads).
    """
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    kubectl_apply(
        name = name,
        manifests = ["@rules_loki//private/manifests:loki.yaml"],
        namespace = namespace,
        create_namespace = True,
        server_side = True,
        wait_for_rollouts = [_LOKI_STS] + list(extra_rollouts),
        wait_timeout = wait_timeout,
        **kwargs
    )

def loki_health_check(
        name,
        namespace = "loki",
        **kwargs):
    """Readiness probe paired with `loki_install`.

    Drops into `itest_service.health_check`.
    """
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    kubectl_apply_health_check(
        name = name,
        namespace = namespace,
        wait_for_rollouts = [_LOKI_STS] + list(extra_rollouts),
        **kwargs
    )
