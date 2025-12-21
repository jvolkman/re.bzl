"""
Tests for regex groups and backreferences.
"""

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//lib/tests:utils.bzl", "run_suite")

def _test_groups_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_groups(env)
    return unittest.end(env)

groups_test = unittest.make(_test_groups_impl)

def run_tests_groups(env):
    """Runs group tests."""
    cases = [
        # 7. Groups and Backreferences (Backreferences not supported, but groups are)
        ("(orange) (apple)", "orange apple", {0: "orange apple", 1: "orange", 2: "apple"}),
        ("(orange) (apple)", "orange banana", None),

        # RE2 Compatibility: Alternative Named Group Syntax
        ("(?<name>abc)", "abc", {0: "abc", "name": "abc"}),

        # Stress Tests: Deeply Nested Groups
        ("((((((((((a))))))))))", "a", {0: "a", 1: "a", 2: "a", 3: "a", 4: "a", 5: "a", 6: "a", 7: "a", 8: "a", 9: "a", 10: "a"}),

        # Stress Tests: Many Named Groups
        ("(?P<g1>a)(?P<g2>b)(?P<g3>c)(?P<g4>d)(?P<g5>e)", "abcde", {0: "abcde", "g1": "a", "g2": "b", "g3": "c", "g4": "d", "g5": "e"}),
    ]
    run_suite(env, "Group Tests", cases)
