"""Maintainer-only: download + extract the Loki helm chart at the sha
pinned in tools/versions.bzl. Consumers never materialize this — the
extension is dev_dependency-gated in MODULE.bazel.
"""

load("//tools:versions.bzl", "LOKI_CHART_VERSIONS")

_BUILD = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "files",
    srcs = glob(["**/*"]),
)
"""

def _impl(rctx):
    version = rctx.attr.version
    if version not in LOKI_CHART_VERSIONS:
        fail("rules_loki: unknown chart version '{}'. Known: {}".format(
            version, sorted(LOKI_CHART_VERSIONS.keys()),
        ))
    pin = LOKI_CHART_VERSIONS[version]
    rctx.download_and_extract(
        url    = pin["chart_url"],
        sha256 = pin["chart_sha256"],
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", _BUILD)

loki_chart_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "version": attr.string(mandatory = True),
    },
)
