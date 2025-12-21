"""
Tests for escaping special characters.
"""

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//lib/tests:utils.bzl", "assert_match")

def _test_escape_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_escape(env)
    return unittest.end(env)

escape_test = unittest.make(_test_escape_impl)

def run_tests_escape(env):
    """Runs escape tests."""

    # 1. Standard Escapes
    assert_match(env, "\\.", ".", ".")
    assert_match(env, "\\*", "*", "*")
    assert_match(env, "\\+", "+", "+")
    assert_match(env, "\\?", "?", "?")
    assert_match(env, "\\\\", "\\", "\\")

    # RE2 Compatibility: Octal Escapes
    assert_match(env, "\\141", "a", "a")
    assert_match(env, "\\000", "\0", "\0")

    # RE2 Compatibility: Additional Escapes
    assert_match(env, "\\a", "\a", "\a")
    assert_match(env, "\\f", "\f", "\f")
    assert_match(env, "\\v", "\v", "\v")

    # RE2 Compatibility: Hex Escapes with Braces
    assert_match(env, "\\x{61}", "a", "a")

    # RE2 Compatibility: POSIX Character Classes
    assert_match(env, "[[:digit:]]+", "123", "123")
    assert_match(env, "[[:^digit:]]+", "abc", "abc")
    assert_match(env, "[[:alpha:]]+", "abcABC", "abcABC")

    # RE2 Compatibility: Quoted Literals
    assert_match(env, "\\Q.*+\\E", ".*+", ".*+")
    assert_match(env, "\\Q.*+\\E", "abc", None)

    # Stress Tests: Large Character Classes
    assert_match(env, "[a-zA-Z0-9_]+", "aZ0_", "aZ0_")

    # Stress Tests: Many Escapes
    assert_match(env, "\\n\\r\\t\\a\\f\\v", "\n\r\t\a\f\v", "\n\r\t\a\f\v")
