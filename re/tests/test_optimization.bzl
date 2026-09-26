"""
Tests for fast-path repetition optimizations.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re:re.bzl", "match")
load("//re/tests:utils.bzl", "assert_span", "run_suite")

def _test_optimization(env):
    run_tests_optimization(env)

def optimization_test(name):
    unit_test(
        name = name,
        impl = _test_optimization,
    )

def run_tests_optimization(env):
    """Runs optimization tests.

    Args:
      env: The test environment.
    """
    cases = [
        # 1. Simple disjoint char loop: a*b
        # Optimized: OP_GREEDY_LOOP('a')
        ("a*b", "aaab", {0: "aaab"}),
        ("a*b", "b", {0: "b"}),
        ("a*b", "aaa", None),  # Missing b

        # 2. Simple disjoint set loop: [a-z]*[0-9]
        # Optimized: OP_GREEDY_LOOP('[a-z]')
        ("[a-z]*[0-9]", "abc1", {0: "abc1"}),
        ("[a-z]*[0-9]", "1", {0: "1"}),
        ("[a-z]*[0-9]", "abc", None),

        # 3. Disjoint set loop: \s*\w
        ("\\s*\\w", "   a", {0: "   a"}),

        # 4. Overlapping (Unsafe) - Should behave correctly (likely standard NFA)
        # [a-z]*a matches "baaa" -> "baaa"
        ("[a-z]*a", "baaa", {0: "baaa"}),
        ("a*a", "aaaa", {0: "aaaa"}),
        ("a*a", "a", {0: "a"}),

        # 5. Overlapping sets
        # [a-z]*[a-f]
        # [a-z]* matches "ag", next [a-f] fails on EOF. Backtrack.
        # [a-z]* matches "a", next "g" fails on [a-f]. Backtrack.
        # [a-z]* matches "", next "a" matches [a-f]. Success.
        # Total match: "a"
        ("[a-z]*[a-f]", "ag", {0: "a"}),

        # 6. Anchors
        # a*$
        ("a*$", "aaa", {0: "aaa"}),
        # search("a*$", "aaab") matches "" at the end (index 4)
        ("a*$", "aaab", {0: ""}),

        # 7. Dot-Star Loop
        (".*a", "baaa", {0: "baaa"}),
        (".*", "abc", {0: "abc"}),

        # 8. Case Insensitive Loop
        ("(?i)a*b", "AAAb", {0: "AAAb"}),
        ("(?i)[a-z]*[0-9]", "ABC1", {0: "ABC1"}),
    ]
    run_suite(env, "Optimization Tests", cases)

    _run_match_fast_path_tests(env)

def _run_match_fast_path_tests(env):
    """Checks that the anchored match() fast path agrees with the NFA."""
    cases = [
        # Lazy loops match as few iterations as possible.
        ("a*?", "aa", (0, 0)),
        ("x[a-c]*?", "xabc", (0, 1)),
        ("x[a-c]+?", "xabc", (0, 2)),
        ("a*?b", "aab", (0, 3)),
        ("[ab]*?b", "aabab", (0, 3)),

        # Case-insensitive loops consume both cases.
        ("(?i)x[a-c]*", "xABC", (0, 4)),
        ("(?i)x[a-z]*?d", "xaDd", (0, 3)),
        ("(?i)x[a-c]*d", "xabDd", (0, 4)),

        # A greedy loop that can consume the suffix backtracks to its last occurrence.
        ("[ab]*b", "abab", (0, 4)),
        ("x[ab]*ab", "xabab", (0, 5)),
        ("x[a-c]*d", "xabcd", (0, 5)),
    ]
    for pattern, text, expected in cases:
        assert_span(env, match(pattern, text), expected, "match(%r, %r)" % (pattern, text))
