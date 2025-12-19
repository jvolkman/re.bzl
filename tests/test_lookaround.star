"""
Tests for regex lookaround assertions.
"""

load("tests/utils.star", "run_suite")

def run_tests_lookaround():
    """Runs lookaround tests."""
    cases = [
        # 19. Lookahead
        ("a(?=b)", "ab", {0: "a"}),
        ("a(?=b)", "ac", None),
        ("a(?!b)", "ac", {0: "a"}),
        ("a(?!b)", "ab", None),
        ("(?=a)a", "a", {0: "a"}),
        ("(?!a)b", "b", {0: "b"}),
        ("(?!a)a", "a", None),

        # 20. Lookbehind
        ("(?<=a)b", "ab", {0: "b"}),
        ("(?<=a)b", "cb", None),
        ("(?<!a)b", "cb", {0: "b"}),
        ("(?<!a)b", "ab", None),
        ("(?<=a.*)b", "axxb", {0: "b"}),
        ("(?<=a.c)d", "abcd", {0: "d"}),
        ("(?<=a)a", "aa", {0: "a"}),
        ("(?<!a)a", "ba", {0: "a"}),
        ("(?<!a)a", "aa", {0: "a"}),

        # 21. Deep Nesting (Stack-Based Verification)
        ("(?=(?=(?=(?=a))))a", "a", {0: "a"}),
        ("(?=(?!(?=(?!a))))a", "a", {0: "a"}),
        ("(?=(?!(?=(?!b))))a", "a", None),
        ("(?=(?!(?=(?!b))))a", "ab", None),
    ]
    run_suite("Lookaround Tests", cases)
