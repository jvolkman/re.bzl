"""
Tests for fast-path repetition optimizations.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re:re.bzl", "compile", "findall", "match", "search", "split", "sub")
load("//re/tests:utils.bzl", "assert_eq", "assert_span", "run_suite")

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
        # A loop before `^` must be able to back off to zero iterations, and one
        # before a multiline `$` must be able to give back a "\n".
        ("a*^", "a", {0: ""}),
        ("(?i)[a-c]*^", "C", {0: ""}),
        ("(?m)\\s*$", " \n x", {0: " "}),
        ("(?m)x\\s*$", "x \n y", {0: "x "}),
        ("(?m)[a\n]*$", "a\n\nb", {0: "a\n"}),
        ("(?m)[ \t]*$", "a \nb", {0: " "}),

        # 7. Dot-Star Loop
        (".*a", "baaa", {0: "baaa"}),
        (".*", "abc", {0: "abc"}),

        # 8. Case Insensitive Loop
        ("(?i)a*b", "AAAb", {0: "AAAb"}),
        ("(?i)[a-z]*[0-9]", "ABC1", {0: "ABC1"}),
    ]
    run_suite(env, "Optimization Tests", cases)

    _run_match_fast_path_tests(env)
    _run_search_end_anchored_tests(env)
    _run_search_suffix_endpos_tests(env)
    _run_first_skip_tests(env)
    _run_windowed_strip_tests(env)
    _run_incomplete_set_tests(env)
    _run_mixed_case_tests(env)

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

        # A loop backs off for `^` and gives back a "\n" for a multiline `$`.
        ("a*^", "aa", (0, 0)),
        ("(?m)\\s*$", " \n x", (0, 1)),
    ]
    for pattern, text, expected in cases:
        assert_span(env, match(pattern, text), expected, "match(%r, %r)" % (pattern, text))

def _run_search_end_anchored_tests(env):
    """Checks the `prefix [set]* suffix$` search fast path."""

    # `[set]+` needs at least one character.
    assert_span(env, search(r"\d+$", "abc"), None, "search \\d+$ without digits")
    assert_span(env, search(r"x[ab]+$", "x"), None, "search x[ab]+$ without set chars")
    assert_span(env, search(r"x[ab]+$", "xab"), (0, 3), "search x[ab]+$")

    # A single prefix set char is not a loop.
    assert_span(env, search(r"[xy][ab]*b$", "zxabab"), (1, 6), "search [xy][ab]*b$")
    assert_span(env, search(r"[xy][ab]*b$", "zabab"), None, "search [xy][ab]*b$ without prefix set char")

    # The match must not start before start_index (later findall/sub/split iterations).
    assert_span(env, compile(r"[ab]*c$").search("abc", 1), (1, 3), "search [ab]*c$ with pos=1")
    assert_eq(env, findall(r"\d+$", "a1b22"), ["22"], "findall \\d+$")
    assert_eq(env, split(r",$", "a,b,"), ["a,b", ""], "split ,$")
    assert_eq(env, sub(r"\s+$", "", "a b  "), "a b", "sub \\s+$")

    # The suffix bypass must still check `$`.
    assert_span(env, search(r"(?i)\s*a$", "cAB"), None, "search (?i)\\s*a$ with suffix not at end")
    assert_span(env, search(r"\s*a$", "a b"), None, "search \\s*a$ with suffix not at end")
    assert_span(env, search(r"(?i)x*a$", "xAxa"), (2, 4), "search (?i)x*a$")
    assert_span(env, search(r"1*?2$", "12 12"), (3, 5), "search 1*?2$")
    assert_eq(env, findall(r"(?i)\s*a$", "a A"), [" A"], "findall (?i)\\s*a$")

def _run_search_suffix_endpos_tests(env):
    """Checks that the suffix search fast path honors endpos."""
    prog = compile("[ab]*c")
    assert_span(env, prog.search("abcab", 0, 2), None, "search [ab]*c with endpos before the suffix")
    assert_span(env, prog.search("abcab", 0, 3), (0, 3), "search [ab]*c with endpos after the suffix")
    assert_span(env, compile(r"\s*;").search("a ;b", 0, 2), None, "search \\s*; with endpos before the suffix")

def _run_first_skip_tests(env):
    """Checks the first-character prefilter used by unanchored search."""
    assert_eq(env, compile("x*").first_skip, None, "no first_skip when the pattern can match empty")
    assert_eq(env, compile(".a").first_skip, None, "no first_skip for patterns starting with .")
    skip = compile(r"a|\bbc").first_skip
    assert_eq(env, "a" in skip or "b" in skip, False, "first_skip excludes possible first chars")
    assert_eq(env, "z" in skip, True, "first_skip includes impossible first chars")

    ci_skip = compile("(?i)a|bc|[d-e]+|f*g").first_skip
    for c in ["a", "A", "b", "B", "d", "D", "e", "E", "f", "F", "g", "G"]:
        assert_eq(env, c in ci_skip, False, "case-insensitive first_skip excludes %r" % c)
    assert_eq(env, "z" in ci_skip and "Z" in ci_skip, True, "case-insensitive first_skip includes z/Z")

    scoped_skip = compile("(?i:a)|B").first_skip
    for c in ["a", "A", "B"]:
        assert_eq(env, c in scoped_skip, False, "scoped first_skip excludes %r" % c)
    assert_eq(env, "b" in scoped_skip, True, "scoped first_skip includes 'b'")

    assert_span(env, search("a|bc", "zzbc"), (2, 4), "search a|bc")
    assert_span(env, search("(?i)a|bc", "zzBC"), (2, 4), "search (?i)a|bc")
    assert_span(env, search(r"\bfoo", "xfoo foo"), (5, 8), "search \\bfoo")
    assert_span(env, search("(?:ab|cd)+e", "xxabcdcde"), (2, 9), "search (?:ab|cd)+e")
    assert_span(env, search("[xy]", "aaa"), None, "search [xy] without candidates")
    assert_span(env, compile("[bc]").search("aab", 0, 2), None, "search [bc] with endpos before the candidate")
    assert_eq(env, findall("[0-9]+", "a1b22c333"), ["1", "22", "333"], "findall [0-9]+")

    # match()/fullmatch() reject in O(1) when the first char cannot begin a match.
    prog = compile("[ab]c")
    assert_span(env, prog.match("xac", 1), (1, 3), "match [ab]c at pos=1")
    assert_span(env, prog.match("xac", 0), None, "match [ab]c at a rejected char")
    ci_prog = compile("(?i)[ab]c")
    assert_span(env, ci_prog.match("xAc", 1), (1, 3), "match (?i)[ab]c at pos=1")
    assert_span(env, ci_prog.match("xAc", 0), None, "match (?i)[ab]c at a rejected char")
    assert_span(env, ci_prog.fullmatch("Bc"), (0, 2), "fullmatch (?i)[ab]c on Bc")
    assert_span(env, ci_prog.fullmatch("xc"), None, "fullmatch (?i)[ab]c on rejected char")
    assert_span(env, compile("a").match("a", 1), None, "match a at the end")
    assert_span(env, compile("ab").fullmatch("ab", 0, 1), None, "fullmatch ab with endpos=1")
    assert_span(env, match("a+", ""), None, "match a+ on empty input")
    assert_span(env, compile(r"\d+").match("ab12", 2), (2, 4), "match \\d+ at pos=2")
    assert_span(env, compile(r"\d+").fullmatch("ab12", 2), (2, 4), "fullmatch \\d+ at pos=2")

def _run_windowed_strip_tests(env):
    """Checks runs of characters that cross the windows of the windowed lstrip/rstrip."""

    # The windows hold 64, 256, 1024, 4096, 16384 and then 65536 characters.
    for n in [63, 64, 65, 320, 1344, 87361]:
        run = "a" * n

        # The first-character prefilter of an unanchored search (lstrip).
        assert_span(env, search(r"\d", run + "1"), (n, n + 1), "search \\d after %d chars" % n)

        # The suffix search fast path (rstrip).
        assert_span(env, search("[ab]*c", run + "c"), (0, n + 1), "search [ab]*c over %d chars" % n)

        # The greedy loop of the match() fast path (lstrip), with and without endpos.
        assert_span(env, match("xa*", "x" + run), (0, n + 1), "match xa* over %d chars" % n)
        assert_span(env, compile("xa*").match("x" + run + "aa", 0, n + 1), (0, n + 1), "match xa* up to endpos over %d chars" % n)

        # A greedy loop in the NFA (lstrip). Its thread steps once per character, so
        # the longest run is skipped.
        if n < 2000:
            assert_span(env, search("(x)a*$", "x" + run), (0, n + 1), "search (x)a*$ over %d chars" % n)
            assert_span(env, match("(x)(?i:a*)$", "x" + run.upper()), (0, n + 1), "match (x)(?i:a*)$ over %d chars" % n)

def _run_incomplete_set_tests(env):
    """Checks that the fast paths don't use a set's all_chars when it's incomplete.

    A set with a negated POSIX class lists only some of its members in all_chars.
    [[:^digit:]] is \\D, so the expected results are CPython's for \\D.
    """
    assert_span(env, match("[[:^digit:]]*", "ab1"), (0, 2), "match [[:^digit:]]*")
    assert_span(env, search("[[:^digit:]]*1", "ab1"), (0, 3), "search [[:^digit:]]*1")
    assert_span(env, match("x[[:^digit:]]*", "xab1"), (0, 3), "match x[[:^digit:]]*")
    assert_span(env, match("[a[:^digit:]]*[[:digit:]]", "ab1"), (0, 3), "match [a[:^digit:]]*[[:digit:]]")
    assert_span(env, search("x[[:^digit:]]*y", "zxaby"), (1, 5), "search x[[:^digit:]]*y")
    assert_span(env, compile("[[:^digit:]]+").fullmatch("ab"), (0, 2), "fullmatch [[:^digit:]]+")
    assert_eq(env, findall("[[:^digit:]]+", "a1bc2"), ["a", "bc"], "findall [[:^digit:]]+")

def _run_mixed_case_tests(env):
    """Checks the fast paths when parts of a pattern differ in case-sensitivity."""
    cases = [
        # A case-insensitive loop can consume a case-sensitive suffix, and vice versa.
        ("(?i:[a-c]*)B", "search", "aBB", (0, 3)),
        ("(?i:[a-c]*)B", "match", "aBB", (0, 3)),
        ("(?i:[a-c]*)B", "fullmatch", "aBB", (0, 3)),
        ("[A-C]*(?i:b)", "search", "ABB", (0, 3)),
        ("[A-C]*(?i:b)", "match", "ABB", (0, 3)),
        ("[A-C]*(?i:b)", "search", "xABbB", (1, 4)),
        ("[a-c]*(?i:B)", "match", "abB", (0, 3)),

        # Only the loop or the suffix ignores case.
        ("(?i:[a-c]*)d", "search", "xaBDd", (4, 5)),
        ("[A-C]*(?i:d)", "match", "ABDd", (0, 3)),

        # match() finds a case-insensitive suffix and checks a case-insensitive loop in
        # either case, but a case-sensitive part only in its own case.
        ("[a-zA-Z]*?(?i:d)", "match", "aDd", (0, 2)),
        ("[a-c]*?(?i:D)", "match", "acdD", (0, 3)),
        ("(?i)x[a-c]*d", "match", "xABCd", (0, 5)),
        ("(?i)x[a-c]*?D", "match", "xAcd", (0, 4)),
        ("(?i:[a-c]*)d", "match", "aBd", (0, 3)),
        ("(?i:[a-c]*)d", "match", "aBDd", None),
        ("x(?i:[a-c]*)D$", "match", "xAbD", (0, 4)),
        ("x(?i:[a-c]*)D$", "match", "xAcd", None),
        ("x[a-c]*(?i:d)$", "match", "xabD", (0, 4)),
        ("x[a-c]*(?i:d)$", "match", "xaBD", None),

        # The suffix search backs up over a case-insensitive prefix set in either case.
        ("(?i)[ab]c", "search", "Ac", (0, 2)),
        ("(?i)[ab]c", "search", "xBC", (1, 3)),
        ("(?i)[ab][cd]*d", "search", "Acd", (0, 3)),
        ("(?i:[ab])c", "search", "Ac", (0, 2)),
        ("(?i:[ab])c", "search", "AC", None),
        ("(?i:[ab])[cd]*C", "search", "xBdC", (1, 4)),
        ("(?i:[ab])[cd]*C", "search", "xBdc", None),
        ("(?i)[ab]c", "match", "Ac", (0, 2)),
        ("(?i)[ab]c", "fullmatch", "BC", (0, 2)),
        ("(?i)x[ab][cd]*", "match", "xBDc", (0, 4)),

        # The prefix set of `[set1][set2]*suffix` can be inside the loop's run.
        ("[ab][bc]*c", "search", "ccbc", (2, 4)),
        ("[ab][bc]*c", "search", "xbcbc", (1, 5)),
        ("[ab][bc]*c", "search", "cca", None),

        # Equal sets that differ in case-sensitivity are not `[set]+`.
        ("(?i:[ab])[ab]*b", "search", "xAab", (1, 4)),
        ("(?i:[ab])[ab]*b", "search", "xAAb", (2, 4)),
        ("(?i:[ab])[ab]*b$", "search", "xAab", (1, 4)),
        ("(?i:[ab])[ab]*b$", "search", "Bb", (0, 2)),
        ("[ab](?i:[ab]*)b", "search", "xaAb", (1, 4)),
    ]
    for pattern, method, text, expected in cases:
        prog = compile(pattern)
        fn = {"fullmatch": prog.fullmatch, "match": prog.match, "search": prog.search}[method]
        assert_span(env, fn(text), expected, "%s(%r, %r)" % (method, pattern, text))
