"""
Tests for core regex functionality.
"""

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//lib/tests:utils.bzl", "run_suite")

def _test_core_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_core(env)
    return unittest.end(env)

core_test = unittest.make(_test_core_impl)

def run_tests_core(env):
    """Runs core tests."""
    cases = [
        # 4. Core functionality
        ("(orange)-(.*)", "orange-rules", {0: "orange-rules", 1: "orange", 2: "rules"}),
        ("(orange|apple)", "orange", {0: "orange", 1: "orange"}),
        ("(orange|apple)", "apple", {0: "apple", 1: "apple"}),
        ("a(b*)c", "abbbc", {0: "abbbc", 1: "bbb"}),
        ("h.llo", "hello", {0: "hello"}),
        ("(o(r(a)n)ge)", "orange", {0: "orange", 1: "orange", 2: "ran", 3: "a"}),

        # 5. Shortcuts
        ("\\d+", "123", {0: "123"}),
        ("\\w+", "Orange_123", {0: "Orange_123"}),
        ("\\s+", " \t", {0: " \t"}),
        ("[\\d]+", "456", {0: "456"}),
        ("[^\\d]+", "abc", {0: "abc"}),

        # 8. Character classes & Ranges
        ("[oa]range", "orange", {0: "orange"}),
        ("[a-z]range", "orange", {0: "orange"}),
        ("[^oa]range", "orange", None),
        ("[^oa]range", "brange", {0: "brange"}),

        # 15. Inverted Classes
        ("\\D+", "123abc456", {0: "abc"}),
        ("\\W+", "abc_123!@#", {0: "!@#"}),
        ("\\S+", "   abc   ", {0: "abc"}),

        # Stress Tests: Many Alternations
        ("a|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z", "z", {0: "z"}),
        ("a|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z", "a", {0: "a"}),
        ("a|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z", "1", None),

        # Stress Tests: Long Literal
        ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", {0: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"}),
    ]
    run_suite(env, "Core Tests", cases)
