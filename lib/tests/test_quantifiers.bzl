"""
Tests for regex quantifiers.
"""

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//lib/tests:utils.bzl", "run_suite")

def _test_quantifiers_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_quantifiers(env)
    return unittest.end(env)

quantifiers_test = unittest.make(_test_quantifiers_impl)

def run_tests_quantifiers(env):
    """Runs quantifier tests."""
    cases = [
        # 2. Lazy vs Greedy in Context
        ("<.*?>", "<tag>content</tag>", {0: "<tag>"}),
        ("<.*>", "<tag>content</tag>", {0: "<tag>content</tag>"}),

        # 6. Repetition Ranges
        ("a{3}", "aaa", {0: "aaa"}),
        ("a{3}", "aa", None),
        ("a{2,4}", "aaa", {0: "aaa"}),
        ("a{2,4}", "a", None),
        ("a{2,}", "aaaaa", {0: "aaaaa"}),
        ("(ab){2}", "abab", {0: "abab", 1: "ab"}),
        ("a{2,4}?", "aaaaa", {0: "aa"}),

        # 11. Quantifiers on groups
        ("(abc)?def", "abcdef", {0: "abcdef", 1: "abc"}),
        ("(abc)?def", "def", {0: "def"}),

        # RE2 Compatibility: Repetitions Edge Cases
        ("a{0,}", "", {0: ""}),
        ("a{0,}", "aaa", {0: "aaa"}),
        ("a{2,}", "a", None),
        ("a{2,}", "aa", {0: "aa"}),
        ("a{2,}", "aaa", {0: "aaa"}),

        # Stress Tests: Large Repetitions
        ("a{100}", "a" * 100, {0: "a" * 100}),
        ("a{100}", "a" * 99, None),
        ("a{50,100}", "a" * 75, {0: "a" * 75}),

        # Stress Tests: Nested Quantifiers
        ("(a*)*", "aaaaa", {0: ""}),  # Matches empty at start due to epsilon limit
        ("(a+)+", "aaaaa", {0: "aaaaa", 1: "aaaaa"}),

        # Stress Tests: Backtracking Stress (NFA should handle)
        ("a?a?a?a?a?a?a?a?a?a?aaaaaaaaaa", "aaaaaaaaaa", {0: "aaaaaaaaaa"}),
    ]
    run_suite(env, "Quantifier Tests", cases)
