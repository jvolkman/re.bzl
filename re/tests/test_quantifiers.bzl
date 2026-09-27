"""
Tests for regex quantifiers.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re:re.bzl", "compile", "findall")
load("//re/tests:utils.bzl", "assert_eq", "run_suite")

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
    _run_empty_iteration_tests(env)
    _run_lazy_loop_reentry_tests(env)

def _run_empty_iteration_tests(env):
    """Checks that a loop stops after an iteration that matched nothing, as CPython does."""
    cases = [
        # (pattern, method, text, span of every group, (-1, -1) if unset)
        # 9. After an empty iteration, another one that would consume isn't tried,
        # even where an inner loop could not repeat the empty match.
        ("(?:a*|.)*", "match", "ab", [(0, 1)]),
        ("(?:(?:)*|.)*", "match", "ab", [(0, 0)]),
        ("(?:(?:a?)*|.)*", "match", "ab", [(0, 1)]),
        ("((?:a?)*|.)*", "match", "bb", [(0, 0), (0, 0)]),
        ("(?:(?:a?)*|(.))*", "match", "bb", [(0, 0), (-1, -1)]),
        ("(?:((?:a?)*)|(.))*", "match", "ab", [(0, 1), (1, 1), (-1, -1)]),
        ("(?:x?(?:a?)*|.)*", "match", "bb", [(0, 0)]),
        ("(?:(?:a?){2,}|.)*", "match", "bb", [(0, 0)]),
        ("(?:(?:a?)*|.)+", "match", "bb", [(0, 0)]),
        ("(?:(?:a?)*|.)*?b", "match", "bb", [(0, 1)]),
        ("(?:()|a)*?", "fullmatch", "a", [(0, 1), (-1, -1)]),

        # The loop still iterates when the rest of the pattern needs it to, and an
        # empty iteration after a non-empty one still sets its groups.
        ("(?:(?:a?)*|.)*$", "match", "bb", [(0, 2)]),
        ("(?:a*|.)*c", "search", "abc", [(0, 3)]),
        ("(a|)*", "match", "aa", [(0, 2), (2, 2)]),

        # 10. A + always tries a second iteration, even after an empty first one.
        ("(?:()|a)+?", "fullmatch", "a", [(0, 1), (0, 0)]),
        ("(?:()|a)+", "fullmatch", "a", [(0, 1), (1, 1)]),
    ]
    _check_spans(env, cases)

def _run_lazy_loop_reentry_tests(env):
    """Checks lazy loops that a loop that can match empty enters twice at one position."""
    cases = [
        # 11. The second entry tries to exit before it consumes, as the first one does.
        ("(a*?)*", "fullmatch", "aa", [(0, 2), (2, 2)]),
        ("(a*?)+", "fullmatch", "aa", [(0, 2), (2, 2)]),
        ("(a*?)*b", "search", "aab", [(0, 3), (2, 2)]),
        ("(.*?)*$", "search", "ab", [(0, 2), (2, 2)]),
        ("\\b(.*?)+$", "search", "a", [(0, 1), (1, 1)]),
        ("(b|[ab]*?)+$", "search", "a", [(0, 1), (1, 1)]),
        ("(b*?x?)+", "fullmatch", "b", [(0, 1), (1, 1)]),
        ("x?(a*?|b+)*", "fullmatch", "bbaaa", [(0, 5), (5, 5)]),
        ("(x|\\B[ab]*|.*?)*$", "search", "xaa1", [(0, 4), (4, 4)]),
        ("(?:.*?|(1|)*|(?:b1|\\B)*?)*a", "fullmatch", "111aa", [(0, 5), (-1, -1)]),
        ("(a*?|.)+.", "fullmatch", "bbbaaa", [(0, 6), (5, 5)]),
        ("a(b*?|x){1,}$", "search", "abab", [(2, 4), (4, 4)]),

        # These matched CPython before, and still do.
        ("(a*?)*?b", "search", "aab", [(0, 3), (1, 2)]),
        ("(?:(a*?)|b)*", "fullmatch", "ab", [(0, 2), (2, 2)]),
    ]
    _check_spans(env, cases)
    assert_eq(
        env,
        findall("((\\w*?\\b)+)\\W*", "2"),
        [("", ""), ("2", ""), ("", "")],
        "findall('((\\\\w*?\\\\b)+)\\\\W*', '2')",
    )

def _check_spans(env, cases):
    for pattern, method, text, expected in cases:
        p = compile(pattern)
        m = {"fullmatch": p.fullmatch, "match": p.match, "search": p.search}[method](text)
        actual = [m.span(g) for g in range(p.group_count + 1)] if m else None
        assert_eq(env, actual, expected, "%s(%r, %r)" % (method, pattern, text))
