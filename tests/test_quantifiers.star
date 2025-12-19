"""
Tests for regex quantifiers.
"""

load("tests/utils.star", "run_suite")

def run_tests_quantifiers():
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
    ]
    run_suite("Quantifier Tests", cases)
