"""
Tests for regex anchors and word boundaries.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re/tests:utils.bzl", "run_suite")

def _test_anchors(env):
    cases = [
        # Basic Anchors
        ("^orange$", "orange", {0: "orange"}),
        ("^orange", "not orange", None),
        ("orange$", "orange juice", None),

        # Absolute Anchors (matched by \A and \z)
        ("\\Aabc", "abc", {0: "abc"}),
        ("\\Aabc", "xabc", None),
        ("abc\\z", "abc", {0: "abc"}),
        ("abc\\z", "abc\n", None),

        # Word Boundaries
        ("\\bcat\\b", "cat", {0: "cat"}),
        ("\\bcat\\b", "scatter", None),
        ("\\Bcat\\B", "scatter", {0: "cat"}),
        ("\\b\\w+\\b", "Orange", {0: "Orange"}),
        ("\\b", " ", None),
        ("\\B", "a", None),
        ("^\\d+(\\.\\d+){0,3}$", "6.0.2.3611", {0: "6.0.2.3611"}),
        ("^\\d+(\\.\\d+){0,3}$", "6.0.2.3611.7", None),
    ]
    run_suite(env, "Anchors & Boundaries", cases)

def anchors_test(name):
    unit_test(
        name = name,
        impl = _test_anchors,
    )
