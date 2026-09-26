"""Tests for root import struct."""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//:re.bzl", "re")
load("//re:re.bzl", compile_func = "compile")

def _test_root_import(env):
    # Test struct access
    r1 = re.compile("a")
    env.expect.that_str(r1.pattern).equals("a")

    # Test direct access (aliased to avoid conflict)
    r2 = compile_func("b")
    env.expect.that_str(r2.pattern).equals("b")

    # Test other functions on struct
    env.expect.that_str(re.search("a", "bat").group(0)).equals("a")
    env.expect.that_str(re.finditer("a", "bat")[0].group(0)).equals("a")

def root_import_test(name):
    unit_test(
        name = name,
        impl = _test_root_import,
    )
