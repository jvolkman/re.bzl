"""
Tests for core regex functionality.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re:re.bzl", "compile", "fullmatch", "match", "search")
load("//re/tests:utils.bzl", "assert_eq", "assert_span", "run_suite")

def _test_core(env):
    run_tests_core(env)

def core_test(name):
    unit_test(
        name = name,
        impl = _test_core,
    )

def run_tests_core(env):
    """Runs core tests.

    Args:
      env: The test environment.
    """
    cases = [
        # 4. Core functionality
        ("(orange)-(.*)", "orange-rules", {0: "orange-rules", 1: "orange", 2: "rules"}),
        ("(orange|apple)", "orange", {0: "orange", 1: "orange"}),
        ("(orange|apple)", "apple", {0: "apple", 1: "apple"}),
        ("a(b*)c", "abbbc", {0: "abbbc", 1: "bbb"}),
        ("h.llo", "hello", {0: "hello"}),
        ("(o(r(a)n)ge)", "orange", {0: "orange", 1: "orange", 2: "ran", 3: "a"}),
        (".+b", "aaaaaabcd", {0: "aaaaaab"}),

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

        # 6. Priority and Leftmost Matching
        ("a|ab", "ab", {0: "a"}),  # NFA/RE2: first branch wins (leftmost)
        ("ab|a", "ab", {0: "ab"}),
        ("a*", "aaa", {0: "aaa"}),  # Greedy
        ("a*?", "aaa", {0: ""}),  # Lazy

        # Loops in an alternation branch must not re-enter the alternation.
        ("a+|b", "ab", {0: "a"}),
        ("[a-z]+|[0-9]+", "ab12", {0: "ab"}),
        ("\\s+|#.*", " #x", {0: " "}),
        ("(?:(?:x|y)+|b)", "xyb", {0: "xy"}),
        ("(?:a+|b)+c", "abac", {0: "abac"}),
        ("(a|ab)(c|bcd)(d*)", "abcd", {0: "abcd", 1: "a", 2: "bcd", 3: ""}),

        # Empty first alternative.
        ("(|b)c", "bc", {0: "bc", 1: "b"}),
        ("(?:|b)c", "bc", {0: "bc"}),

        # 7. Stress Tests: Long Literal
        ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", {0: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"}),
        (".*", "abc\ndef", {0: "abc"}),  # Dot without s flag

        # 8. A float
        (r"^[+-]?\d+(?:_\d+)*(?:\.\d+(?:_\d+)*)?(?:[eE][+-]?\d+(?:_\d+)*)?", "4.666", {0: "4.666"}),
    ]
    run_suite(env, "Core Tests", cases)

    _run_overlapping_literal_tests(env)

def _run_overlapping_literal_tests(env):
    """Checks literals that match at overlapping positions, such as "AA" in "AAA".

    The threads that match such a literal at two positions resume at two indices, so
    one must not displace the other.
    """
    assert_span(env, search(r"[^A]*AA\d", "CCCCAAA2"), (5, 8), "search [^A]*AA\\d")
    assert_span(env, search(r"(?i)[^a]*AA\d", "CCCCAAA2"), (5, 8), "search (?i)[^a]*AA\\d")
    assert_span(env, search("a$|xx$", "xxx"), (1, 3), "search a$|xx$")
    assert_span(env, search(r"- \d$|x{2}$", "----xxx"), (5, 7), "search - \\d$|x{2}$")
    assert_span(env, search("[^A]*AAb*c", "CAAAbc"), (2, 6), "search [^A]*AAb*c (a loop after the literal)")
    m = search(r"x*?(AA)(\d)", "xAAA2")
    assert_eq(env, m.groups() if m else None, ("AA", "2"), "search x*?(AA)(\\d) groups")

    # Both threads start at the same index.
    assert_span(env, match(r".*?AA\d", "AAA2"), (0, 4), "match .*?AA\\d")
    assert_span(env, fullmatch(r"(?:A|C)*?AA\d", "CAAA2"), (0, 5), "fullmatch (?:A|C)*?AA\\d")

    # endpos ends the input between the two occurrences of the literal.
    prog = compile(r"\D+bb")
    assert_span(env, prog.search("CCbbbb22", 0, 5), (0, 5), "search \\D+bb with endpos")
    assert_span(env, prog.match("CCbbbb22", 0, 5), (0, 5), "match \\D+bb with endpos")
    assert_span(env, prog.search("CCbbbb22"), (0, 6), "search \\D+bb without endpos")
    assert_span(env, compile("(?i)[a-z]+bb").search("CCBBBB22", 0, 5), (0, 5), "search (?i)[a-z]+bb with endpos")
