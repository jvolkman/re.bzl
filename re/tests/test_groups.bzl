"""
Tests for regex groups and backreferences.
"""

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//re/tests:utils.bzl", "run_suite")

def _test_groups_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_groups(env)
    return unittest.end(env)

groups_test = unittest.make(_test_groups_impl)

def run_tests_groups(env):
    """Runs group tests.

    Args:
      env: The test environment.
    """
    cases = [
        # 7. Groups and Backreferences (Backreferences not supported, but groups are)
        ("(orange) (apple)", "orange apple", {0: "orange apple", 1: "orange", 2: "apple"}),
        ("(orange) (apple)", "orange banana", None),

        # Non-capturing Groups
        ("(?:a)(b)", "ab", {0: "ab", 1: "b"}),
        ("a(?:b|c)d", "acd", {0: "acd"}),

        # Unmatched Optional Groups
        ("(a)?(b)", "b", {0: "b", 1: None, 2: "b"}),
        ("((a)|(b))", "b", {0: "b", 1: "b", 2: None, 3: "b"}),

        # Nested Named Groups
        ("(?P<outer>a(?P<inner>b)c)", "abc", {0: "abc", "outer": "abc", "inner": "b"}),

        # RE2 Compatibility: Alternative Named Group Syntax
        ("(?<name>abc)", "abc", {0: "abc", "name": "abc"}),

        # Stress Tests: Deeply Nested Groups
        ("((((((((((a))))))))))", "a", {0: "a", 1: "a", 2: "a", 3: "a", 4: "a", 5: "a", 6: "a", 7: "a", 8: "a", 9: "a", 10: "a"}),

        # Stress Tests: Many Named Groups
        ("(?P<g1>a)(?P<g2>b)(?P<g3>c)(?P<g4>d)(?P<g5>e)", "abcde", {0: "abcde", "g1": "a", "g2": "b", "g3": "c", "g4": "d", "g5": "e"}),

        # Realistic: URI Parsing
        # ^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?
        # Groups:
        # 2: scheme
        # 4: authority
        # 5: path
        # 7: query
        # 9: fragment
        (
            r"^((?P<scheme>[^:/?#]+):)?(//(?P<authority>[^/?#]*))?(?P<path>[^?#]*)(\?(?P<query>[^#]*))?(#(?P<fragment>.*))?",
            "https://www.google.com/search?q=bazel#frag",
            {
                0: "https://www.google.com/search?q=bazel#frag",
                "scheme": "https",
                "authority": "www.google.com",
                "path": "/search",
                "query": "q=bazel",
                "fragment": "frag",
            },
        ),
    ]
    run_suite(env, "Group Tests", cases)
