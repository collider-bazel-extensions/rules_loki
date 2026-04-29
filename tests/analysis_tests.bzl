"""Analysis-time test. Verifies the loki_install macro instantiates a
target with an executable DefaultInfo without invoking kubectl."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_loki//:defs.bzl", "loki_install")

def _has_executable_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(
        env,
        target[DefaultInfo].files_to_run.executable != None,
        "expected target to expose an executable",
    )
    return analysistest.end(env)

_has_executable_test = analysistest.make(_has_executable_impl)

def loki_install_test_suite(name):
    loki_install(
        name = name + "_subject",
        tags = ["manual"],
    )
    _has_executable_test(name = name + "_executable", target_under_test = ":" + name + "_subject")
    native.test_suite(name = name, tests = [":" + name + "_executable"])
