"""
Tests for regex quantifiers.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re/tests:utils.bzl", "run_suite")

def _test_quantifiers(env):
    run_tests_quantifiers(env)

def quantifiers_test(name):
    unit_test(
        name = name,
        impl = _test_quantifiers,
    )

def run_tests_quantifiers(env):
    """Runs quantifier tests.

    Args:
      env: The test environment.
    """
    cases = [
        # 1. Basic Greedy vs Lazy
        ("a{2,4}", "aa", {0: "aa"}),
        ("a{2,4}", "aaa", {0: "aaa"}),
        ("a{2,4}", "aaaa", {0: "aaaa"}),
        ("a{2,4}", "aaaaa", {0: "aaaa"}),
        ("a{2,4}?", "aaaaa", {0: "aa"}),

        # 2. Lazy vs Greedy in Context
        ("<.*?>", "<tag>content</tag>", {0: "<tag>"}),
        ("<.*>", "<tag>content</tag>", {0: "<tag>content</tag>"}),

        # 3. Repeat Range Edge Cases
        ("a{0,}", "", {0: ""}),
        ("a{0,}", "aaa", {0: "aaa"}),
        ("a{2,}", "a", None),
        ("a{2,}", "aa", {0: "aa"}),
        ("a{2,}", "aaa", {0: "aaa"}),
        ("a{,2}", "aaa", {0: "aa"}),
        ("a{,2}", "a", {0: "a"}),

        # 4. Group Quantifiers
        ("(ab){2}", "abab", {0: "abab", 1: "ab"}),
        ("(abc)?def", "abcdef", {0: "abcdef", 1: "abc"}),
        ("(abc)?def", "def", {0: "def"}),
        ("(a+)+", "aaaaa", {0: "aaaaa", 1: "aaaaa"}),
        ("(a*)*", "aaaaa", {0: "aaaaa", 1: ""}),  # Nested stars
        ("(a*)*", "", {0: "", 1: ""}),
        ("(a?)*", "aaa", {0: "aaa", 1: ""}),
        ("(a|)+", "aaa", {0: "aaa", 1: ""}),  # Empty alternation match

        # 5. Overlapping / Non-trivial Quantifiers
        ("a{2,3}a{2,3}", "aaaa", {0: "aaaa"}),
        ("a{2,3}a{2,3}", "aaaaa", {0: "aaaaa"}),
        ("a{2,3}a{2,3}", "aaaaaa", {0: "aaaaaa"}),
        ("a{2,3}a{2,3}", "aaa", None),

        # 6. Stress and Backtracking
        ("a?a?a?a?a?a?a?a?a?a?aaaaaaaaaa", "aaaaaaaaaa", {0: "aaaaaaaaaa"}),
        ("a{100}", "a" * 100, {0: "a" * 100}),
        ("a{100}", "a" * 99, None),
        # 7. Regression: Greedy match with optional group at end
        (r"\d{4}-\d{2}-\d{2}(?:[Tt ]\d{2}:\d{2})?", "1979-05-27T07:32", {0: "1979-05-27T07:32"}),

        # 8. An empty optional group at the start of a repeated group: `(?:(?:)?a)+`
        # is `a+`, not `a*?`.
        ("(?:(?:)?a)+b", "b", None),
        ("(?:(?:)?\\d)+", "a12", {0: "12"}),
        ("(?:(?:)??a)+?", "xaab", {0: "a"}),
    ]
    run_suite(env, "Quantifier Tests", cases)
