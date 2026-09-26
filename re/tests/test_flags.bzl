"""
Tests for regex flags.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//:re.bzl", "re")
load("//re/tests:utils.bzl", "assert_span", "run_suite")

def _test_flags(env):
    # 1. Inline Flags
    inline_cases = [
        ("(?i)orange", "OrAnGe", {0: "OrAnGe"}),
        ("(?i)[a-z]+", "ORANGE", {0: "ORANGE"}),
        ("(?i)a", "A", {0: "A"}),
        ("(?i)[^a]", "A", None),

        # Scoped Flags
        ("(?i:a)b", "Ab", {0: "Ab"}),
        ("(?i:a)b", "AB", None),
        ("(?i:a)b", "ab", {0: "ab"}),
        ("(?i:a(?-i:b)c)", "Abc", {0: "Abc"}),
        ("(?i:a(?-i:b)c)", "AbC", {0: "AbC"}),

        # Ungreedy Flag (Inline)
        ("(?U)a*", "aaa", {0: ""}),
        ("(?U)a*?", "aaa", {0: "aaa"}),
        ("(?U)a+", "aaa", {0: "a"}),
        ("(?U)a+?", "aaa", {0: "aaa"}),
        ("(?U)a{1,3}", "aaa", {0: "a"}),
        ("(?U:a*)b", "aaab", {0: "aaab"}),

        # Multiline Flag (Inline)
        ("(?m)^line", "line1\nline2", {0: "line"}),
        ("(?m)^line2", "line1\nline2", {0: "line2"}),
        ("(?m)end$", "start\nend", {0: "end"}),
        ("(?m)^a", "b\na", {0: "a"}),
        ("(?m)a$", "a\nb", {0: "a"}),
        ("(?m)^$", "\n", {0: ""}),
        ("(?m)^$", "a\n\nb", {0: ""}),

        # Dot-All Flag (Inline)
        ("(?s).+", "line1\nline2", {0: "line1\nline2"}),
        ("(?-s).+", "line1\nline2", {0: "line1"}),

        # Combined Flags (Inline)
        ("(?ms)^a.b$", "a\nb", {0: "a\nb"}),

        # Stress Tests: Many Flags and Scoped Groups
        ("(?i:a(?m:b(?s:c(?U:d*))))", "Abcd", {0: "Abc"}),
        ("(?i:A(?m:B(?s:C(?U:D*))))", "abcd", {0: "abc"}),
    ]
    run_suite(env, "Inline Flags", inline_cases)

    # 2. Flags Parameter (API)
    # Using run_suite with 4-element tuples for simplicity in this grouping
    api_cases = [
        # IGNORECASE
        ("abc", "ABC", {0: "ABC"}, re.I),
        ("abc", "ABC", {0: "ABC"}, re.IGNORECASE),
        ("abc", "ABC", None),  # Default is CS

        # MULTILINE
        ("^line2", "line1\nline2", {0: "line2"}, re.M),
        ("^line2", "line1\nline2", None),

        # DOTALL
        ("a.b", "a\nb", {0: "a\nb"}, re.S),
        ("a.b", "a\nb", None),

        # UNGREEDY
        ("a*", "aaa", {0: "aaa"}),  # Default is greedy
        ("a*", "aaa", {0: ""}, re.U),
        ("a*", "aaa", {0: ""}, re.UNGREEDY),

        # VERBOSE
        (" a b c ", "abc", {0: "abc"}, re.X),
        (" a b c ", "abc", {0: "abc"}, re.VERBOSE),

        # Combined
        ("^ABC", "line1\nabc", {0: "abc"}, re.I | re.M),
        ("a.b", "A\nB", {0: "A\nB"}, re.I | re.S),

        # UNICODE (no-op)
        ("abc", "abc", {0: "abc"}, re.UNICODE),
    ]
    run_suite(env, "API Flags", api_cases)

    # 3. Case-insensitive match()/fullmatch() (characters are lowered on demand)
    assert_span(env, re.compile("(?i)true|false").match("x TRUE", 2), (2, 6), "CI string at pos")
    assert_span(env, re.compile("(?i)[a-c]+d").match("ABCD"), (0, 4), "CI greedy set loop")
    assert_span(env, re.compile("(?i)a[b-d]*?e").match("ABCDE"), (0, 5), "CI lazy set loop")
    assert_span(env, re.compile("(?i)x[a-c]*y|z").match("XaBcY"), (0, 5), "CI loop in alternation")
    assert_span(env, re.compile(r"(?i)\bnull\b").match("NULL,"), (0, 4), "CI string with word boundaries")
    assert_span(env, re.compile("(?i)ab").fullmatch("xAB", 1), (1, 3), "CI fullmatch at pos")
    assert_span(env, re.compile("(?i)abc|x").match("ABCD", 0, 2), None, "CI string past endpos")

    # 4. fullmatch() with scoped flags: only the scoped part is case-insensitive
    assert_span(env, re.fullmatch("(?i:x)[a-z]+", "xAB"), None, "CS loop after CI prefix")
    assert_span(env, re.fullmatch("(?i:x)[a-z]+", "Xab"), (0, 3), "CI prefix before CS loop")
    assert_span(env, re.fullmatch("(?i)x(?-i:[a-z]+)", "xAB"), None, "CS loop after (?-i:")
    assert_span(env, re.fullmatch("(?i:x)[a-z]*C", "xabc"), None, "CS suffix after CI prefix")
    assert_span(env, re.fullmatch("(?i:x)[a-c]", "xA"), None, "CS set after CI prefix")
    assert_span(env, re.fullmatch("x(?i:[a-c]*)", "xAbC"), (0, 4), "CI loop after CS prefix")
    assert_span(env, re.fullmatch("(?i)x[a-c]+", "XABC"), (0, 4), "all CI")
    assert_span(env, re.fullmatch("(?i)ab[0-9]*CD", "AB12cd"), (0, 6), "all CI with suffix")

def flags_test(name):
    unit_test(
        name = name,
        impl = _test_flags,
    )
