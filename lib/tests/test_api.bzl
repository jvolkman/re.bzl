"""
Tests for the high-level API functions: findall, sub, split.
"""

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//lib:re.bzl", "compile", "findall", "fullmatch", "match", "search", "split", "sub")
load("//lib/tests:utils.bzl", "assert_eq")

def _test_api_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_api(env)
    return unittest.end(env)

api_test = unittest.make(_test_api_impl)

def run_tests_api(env):
    """Runs API tests."""

    # 1. search vs match vs fullmatch
    assert_eq(env, bool(search("abc", "xabcy")), True, "search should find in middle")
    assert_eq(env, bool(match("abc", "xabcy")), False, "match should only find at start")
    assert_eq(env, bool(match("abc", "abcy")), True, "match should find at start")
    assert_eq(env, bool(fullmatch("abc", "abc")), True, "fullmatch should match entire string")
    assert_eq(env, bool(fullmatch("abc", "abcy")), False, "fullmatch should not match partial")

    # 2. findall
    assert_eq(env, findall("a+", "aa aba a"), ["aa", "a", "a", "a"], "findall simple")
    assert_eq(env, findall(r"(\w+)=(\d+)", "a=1 b=2"), [("a", "1"), ("b", "2")], "findall with groups")

    # 3. sub
    assert_eq(env, sub("a+", "b", "aaabaa"), "bbb", "sub simple")
    assert_eq(env, sub(r"(\w+)=(\d+)", r"\2=\1", "a=1 b=2"), "1=a 2=b", "sub with backrefs")

    # 4. split
    assert_eq(env, split(r"\s+", "a b  c"), ["a", "b", "c"], "split simple")
    assert_eq(env, split(r"(\s+)", "a b  c"), ["a", " ", "b", "  ", "c"], "split with groups")

    # 5. Compilation reuse
    prog = compile("a+")
    assert_eq(env, bool(prog.search("aaa")), True, "compiled search")
    assert_eq(env, bool(prog.match("aaa")), True, "compiled match")

    # Stress Tests: API with Large Inputs
    large_input = "a" * 1000 + "b" + "a" * 1000
    assert_eq(env, bool(search("b", large_input)), True, "search in large input")
    assert_eq(env, len(findall("a+", large_input)), 2, "findall in large input")
    assert_eq(env, sub("a+", "c", large_input), "cbc", "sub in large input")
    assert_eq(env, split("b", large_input), ["a" * 1000, "a" * 1000], "split in large input")
