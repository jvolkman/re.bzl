"""
Tests for regex anchors and word boundaries.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re:re.bzl", "compile", "findall", "split", "sub")
load("//re/tests:utils.bzl", "assert_eq", "assert_span", "run_suite")

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

    # `^` and `\A` only match at index 0, not at a later start position.
    assert_eq(env, findall("^a", "aaa"), ["a"], "findall ^a")
    assert_eq(env, findall(r"^\d+", "12 34"), ["12"], "findall ^\\d+")
    assert_eq(env, findall("(?m)^a", "a\na"), ["a", "a"], "findall (?m)^a still matches every line")
    assert_eq(env, sub(r"^\s", "", "   x"), "  x", "sub ^\\s")
    assert_eq(env, split("^a", "aaa"), ["", "aa"], "split ^a")
    prog = compile("^a")
    assert_span(env, prog.search("aa", 1), None, "search ^a with pos=1")
    assert_span(env, prog.match("aa", 1), None, "match ^a with pos=1")
    assert_span(env, prog.fullmatch("aa", 1), None, "fullmatch ^a with pos=1")
    assert_span(env, compile(r"^\w+").match("ab cd", 3), None, "match ^\\w+ with pos=3")
    assert_span(env, compile(r"\Aab").search("abab", 2), None, "search \\Aab with pos=2")

def anchors_test(name):
    unit_test(
        name = name,
        impl = _test_anchors,
    )
