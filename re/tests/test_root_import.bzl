"""Tests for root import struct."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//:re.bzl", "re")
load("//re:re.bzl", compile_func = "compile")

def _test_root_import_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_root_import(env)
    return unittest.end(env)

root_import_test = unittest.make(_test_root_import_impl)

def run_tests_root_import(env):
    """Runs tests for the root 're' struct.

    Args:
      env: The test environment.
    """

    # Test struct access
    r1 = re.compile("a")
    asserts.equals(env, "a", r1.pattern)

    # Test direct access (aliased to avoid conflict)
    r2 = compile_func("b")
    asserts.equals(env, "b", r2.pattern)

    # Test other functions on struct
    asserts.equals(env, re.search("a", "ba").group(0), "a")
