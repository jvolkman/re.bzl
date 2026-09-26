"""
Tests for the high-level API functions: findall, sub, split.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re:re.bzl", "compile", "findall", "fullmatch", "match", "search", "split", "sub")
load("//re/tests:utils.bzl", "assert_eq", "assert_span")

def _test_api(env):
    run_tests_api(env)

def api_test(name):
    unit_test(
        name = name,
        impl = _test_api,
    )

def run_tests_api(env):
    """Runs API tests.

    Args:
      env: The test environment.
    """

    # 1. search vs match vs fullmatch
    assert_eq(env, bool(search("abc", "xabcy")), True, "search should find in middle")
    assert_eq(env, bool(match("abc", "xabcy")), False, "match should only find at start")
    assert_eq(env, bool(match("abc", "abcy")), True, "match should find at start")
    assert_eq(env, bool(fullmatch("abc", "abc")), True, "fullmatch should match entire string")
    assert_eq(env, bool(fullmatch("abc", "abcy")), False, "fullmatch should not match partial")

    # 2. findall
    assert_eq(env, findall("a+", "aa aba a"), ["aa", "a", "a", "a"], "findall simple")
    assert_eq(env, findall(r"(\w+)=(\d+)", "a=1 b=2"), [("a", "1"), ("b", "2")], "findall with groups")

    # 3. sub
    assert_eq(env, sub("a+", "b", "aaabaa"), "bbb", "sub simple")
    assert_eq(env, sub(r"(\w+)=(\d+)", r"\2=\1", "a=1 b=2"), "1=a 2=b", "sub with backrefs")

    # 4. split
    assert_eq(env, split(r"\s+", "a b  c"), ["a", "b", "c"], "split simple")
    assert_eq(env, split(r"(\s+)", "a b  c"), ["a", " ", "b", "  ", "c"], "split with groups")

    # 5. Compilation reuse
    prog = compile("a+")
    assert_eq(env, bool(prog.search("aaa")), True, "compiled search")
    assert_eq(env, bool(prog.match("aaa")), True, "compiled match")

    # 6. lastindex and lastgroup
    m = search(r"(a)(b)", "ab")
    assert_eq(env, m.lastindex, 2, "lastindex for (a)(b)")
    assert_eq(env, m.lastgroup, None, "lastgroup for (a)(b)")

    m = search(r"(?P<first>a)(?P<second>b)", "ab")
    assert_eq(env, m.lastindex, 2, "lastindex for named groups")
    assert_eq(env, m.lastgroup, "second", "lastgroup for named groups")

    m = search(r"((a)(b))", "ab")
    assert_eq(env, m.lastindex, 1, "lastindex for nested groups (outermost wins last)")
    # Actually, in Python:
    # re.search('((a)(b))', 'ab').lastindex -> 1
    # Because group 1 is the last one to *close*.
    # Wait, (a) is group 2, (b) is group 3.
    # ((a)(b))
    # ^ ^  ^ ^
    # 1 2  2 3 3 1
    # Order of closing: 2, 3, 1. So lastindex should be 1.

    m = search(r"(a)|(b)", "b")
    assert_eq(env, m.lastindex, 2, "lastindex for alternation")

    m = search(r"(?P<name>a)|(b)", "a")
    assert_eq(env, m.lastgroup, "name", "lastgroup for alternation")

    # 7. has_case_insensitive optimization flag
    m1 = search("abc", "abc")
    assert_eq(env, m1.re.has_case_insensitive, False, "case sensitive should not have flag")
    m2 = search("(?i)abc", "abc")
    assert_eq(env, m2.re.has_case_insensitive, True, "case insensitive should have flag")

    # 8. opt optimization struct
    m3 = match(r"^1\w*", "1ccc")
    assert_eq(env, m3.re.opt != None, True, "should have opt struct for ^prefix[set]*")
    assert_eq(env, m3.re.opt.prefix, "1", "opt.prefix should be 1")
    assert_eq(env, "c" in m3.re.opt.greedy_set_chars, True, "opt.greedy_set_chars should include c")

    # 9. Suffix optimization
    m4 = match(r"^\d+abc$", "123abc")
    assert_eq(env, m4.re.opt != None, True, "should have opt struct for suffix")
    assert_eq(env, m4.re.opt.suffix, "abc", "opt.suffix should be abc")
    assert_eq(env, m4.re.opt.is_anchored_end, True, "opt.is_anchored_end should be True")
    assert_eq(env, m4.group(0), "123abc", "match result correct")

    m5 = fullmatch(r"^\d+abc$", "123abc")
    assert_eq(env, m5 != None, True, "fullmatch suffix")
    assert_eq(env, m5.group(0), "123abc", "fullmatch result correct")

    # 10. Search optimizations
    m6 = search(r"\d+abc$", "x123abc")
    assert_eq(env, m6.re.opt != None, True, "should have opt struct for end-anchored search")
    assert_eq(env, m6.group(0), "123abc", "end-anchored search match")
    assert_eq(env, m6.start(), 1, "end-anchored search start")

    m7 = search(r"a\w+b", "xa123by")
    assert_eq(env, m7.re.opt != None, True, "should have opt struct for literal skip")
    assert_eq(env, m7.group(0), "a123b", "literal skip search match")
    assert_eq(env, m7.start(), 1, "literal skip search start")

    # 11. Edge cases and bail-outs
    # Search anchored at start should delegate to match optimization
    m8 = search(r"^abc\d+", "abc123xy")
    assert_eq(env, m8.re.opt != None, True, "anchored search should be optimized")
    assert_eq(env, m8.group(0), "abc123", "anchored search result")

    # Pure literal skip
    m9 = search(r"needle", "haystack needle haystack")
    assert_eq(env, m9.re.opt != None, True, "pure literal search should be optimized")
    assert_eq(env, m9.group(0), "needle", "pure literal match")

    # Non-optimized complex case (alternation)
    m10 = search(r"abc|def", "abc")

    # Alternation is currently not optimized in opt struct
    assert_eq(env, m10.re.opt == None, True, "complex alternation should NOT have opt")
    assert_eq(env, m10.group(0), "abc", "complex search still works")

    # 12. Match Object Methods: groups() and span()
    m_full = search(r"(\w+) (\w+)", "hello world")
    assert_eq(env, m_full.groups(), ("hello", "world"), "groups() should return all subgroups")
    assert_eq(env, m_full.groups("none"), ("hello", "world"), "groups() with default should not affect matched groups")

    m_partial = search(r"(a)?(b)", "b")
    assert_eq(env, m_partial.groups(), (None, "b"), "groups() should return None for unmatched")
    assert_eq(env, m_partial.groups("miss"), ("miss", "b"), "groups() should return default for unmatched")

    assert_eq(env, m_full.span(0), (0, 11), "span(0) for 'hello world'")
    assert_eq(env, m_full.span(1), (0, 5), "span(1) for 'hello'")
    assert_eq(env, m_full.span(2), (6, 11), "span(2) for 'world'")
    assert_eq(env, m_partial.span(1), (-1, -1), "span() for unmatched group should be (-1, -1)")

    # 13. Named Group Edge Cases
    # Starlark doesn't allow duplicate keys in dict, but regex might.
    # RE2/Python: (?P<name>a)(?P<name>b) is usually an error or last one wins.
    # Our implementation: named_groups[group_name] = gid. Last one wins.
    m_named = search(r"(?P<n>a)(?P<n>b)", "ab")
    assert_eq(env, m_named.group("n"), "b", "last named group wins in case of duplicates")
    assert_eq(env, m_named.lastgroup, "n", "lastgroup should be n")

    # Match in one branch of alternation but not another
    m_alt = search(r"(?P<left>a)|(?P<right>b)", "b")
    assert_eq(env, m_alt.group("left"), None, "unmatched named group should return None")
    assert_eq(env, m_alt.group("right"), "b", "matched named group should return value")
    assert_eq(env, m_alt.lastgroup, "right", "lastgroup should be the matched named group")

    # 14. endpos support
    assert_eq(env, bool(search("abc", "xabcy", endpos = 4)), True, "search with endpos (exact)")
    assert_eq(env, bool(search("abc", "xabcy", endpos = 3)), False, "search with endpos (too early)")
    assert_eq(env, bool(match("abc", "abcy", endpos = 3)), True, "match with endpos (exact)")
    assert_eq(env, bool(match("abc", "abcy", endpos = 2)), False, "match with endpos (too early)")
    assert_eq(env, bool(fullmatch("abc", "abc", endpos = 3)), True, "fullmatch with endpos (exact)")
    assert_eq(env, bool(fullmatch("abc", "abc", endpos = 2)), False, "fullmatch with endpos (too early)")

    # endpos on compiled object
    prog = compile("abc")
    assert_eq(env, bool(prog.search("xabcy", endpos = 4)), True, "compiled search with endpos")
    assert_eq(env, bool(prog.match("abcy", endpos = 3)), True, "compiled match with endpos")
    assert_eq(env, bool(prog.fullmatch("abc", endpos = 3)), True, "compiled fullmatch with endpos")

    # endpos should act as the end of the string for anchors
    assert_eq(env, bool(search("abc$", "xabcy", endpos = 4)), True, "endpos works with $ anchor")
    assert_eq(env, bool(match(r"abc\b", "abc.def", endpos = 3)), True, "endpos works with \b boundary")

    # 15. groupdict()
    m_dict = search(r"(?P<first>a)(?P<second>b)", "ab")
    assert_eq(env, m_dict.groupdict(), {"first": "a", "second": "b"}, "groupdict returns correct dict")

    m_dict_partial = search(r"(?P<first>a)?(?P<second>b)", "b")
    assert_eq(env, m_dict_partial.groupdict(), {"first": None, "second": "b"}, "groupdict handles unmatched groups")
    assert_eq(env, m_dict_partial.groupdict("default"), {"first": "default", "second": "b"}, "groupdict uses default for unmatched")

    m_no_named = search(r"(a)(b)", "ab")
    assert_eq(env, m_no_named.groupdict(), {}, "groupdict returns empty dict if no named groups")

    # 16. fullmatch keeps exploring until a match ends at the end of the string
    assert_span(env, fullmatch("a|ab", "ab"), (0, 2), "fullmatch tries later alternatives")
    assert_span(env, fullmatch(r"\w+?", "abc"), (0, 3), "fullmatch extends lazy loops")
    assert_span(env, fullmatch("a+?", "aa"), (0, 2), "fullmatch extends lazy char loops")
    assert_span(env, fullmatch("(?:a|ab)(?:c|bcd)", "abcd"), (0, 4), "fullmatch backtracks into alternation")
    assert_span(env, fullmatch("a|ab", "abc"), None, "fullmatch still rejects partial matches")
    assert_span(env, compile("a|ab").fullmatch("abc", endpos = 2), (0, 2), "fullmatch respects endpos")
    m_fm = fullmatch("(a|ab)(c|bcd)?", "abcd")
    assert_eq(env, m_fm.groups() if m_fm else None, ("a", "bcd"), "fullmatch groups from the full-length path")
    m_fm = fullmatch(r"(a+?)(a*?)", "aaa")
    assert_eq(env, m_fm.groups() if m_fm else None, ("a", "aa"), "fullmatch groups with lazy loops")

    # 17. Empty matches (Python 3.7+): a non-empty match may start where the previous
    # empty match ended, and an empty match is never repeated at the same position.
    assert_eq(env, findall("c??", "ca-"), ["", "c", "", "", ""], "findall lazy empty then non-empty")
    assert_eq(env, findall(r"\b|\w+", "ab"), ["", "ab", ""], "findall empty alternative first")
    assert_eq(env, findall("|a", "aa"), ["", "a", "", "a", ""], "findall empty branch first")
    assert_eq(env, findall("a|", "aa"), ["a", "a", ""], "findall empty match after non-empty")
    assert_eq(env, findall("x*", "abxd"), ["", "", "x", "", ""], "findall x*")
    assert_eq(env, findall(r"\d*?", "1a"), ["", "1", "", ""], "findall lazy loop")
    assert_eq(env, findall("(?m)^|x", "x\nx"), ["", "x", "", "x"], "findall (?m)^|x")
    assert_eq(env, findall("(?i)A|", "aA"), ["a", "A", ""], "findall case-insensitive")
    assert_eq(env, findall("", ""), [""], "findall empty pattern on empty text")
    assert_eq(env, findall("", "ab"), ["", "", ""], "findall empty pattern")
    assert_eq(env, findall("^a*", "b"), [""], "findall ^a* matches empty once")
    assert_eq(env, findall("^a*?", "ab"), ["", "a"], "findall ^a*? extends after the empty match")
    assert_eq(env, findall("^(?:|a)", "ab"), ["", "a"], "findall ^(?:|a)")
    assert_eq(env, findall("a*$", "baa"), ["aa", ""], "findall a*$")

    assert_eq(env, sub("x*", "-", "abxd"), "-a-b--d-", "sub x*")
    assert_eq(env, sub("", "-", "ab"), "-a-b-", "sub empty pattern")
    assert_eq(env, sub(r"\b|\w+", "-", "ab cd"), "--- ---", "sub empty alternative first")
    assert_eq(env, sub("a*?", "-", "baac"), "-b-----c-", "sub lazy loop")
    assert_eq(env, sub("x*", "-", "abxd", count = 2), "-a-bxd", "sub x* with count")
    assert_eq(env, sub(r"^\s*", "", "ab"), "ab", "sub ^\\s* without leading space")
    assert_eq(env, sub(r"^\s*", "", "  ab"), "ab", "sub ^\\s* with leading space")

    assert_eq(env, split(r"\W*", "...words..."), ["", "", "w", "o", "r", "d", "s", "", ""], "split \\W*")
    assert_eq(env, split(r"(\W*)", "...words..."), ["", "...", "", "", "w", "", "o", "", "r", "", "d", "", "s", "...", "", "", ""], "split (\\W*)")
    assert_eq(env, split(r"\b", "a b"), ["", "a", " ", "b", ""], "split \\b")
    assert_eq(env, split("x*", "axbc"), ["", "a", "", "b", "c", ""], "split x*")
    assert_eq(env, split("x*", "axbc", maxsplit = 2), ["", "a", "bc"], "split x* with maxsplit")
    assert_eq(env, split("(?i)a*?", "bAc"), ["", "b", "", "", "c", ""], "split case-insensitive lazy loop")
    assert_eq(env, split("(a)|b*", "cabd"), ["", None, "c", "a", "", None, "", None, "d", None, ""], "split keeps None for unmatched groups")
    assert_eq(env, split("", "ab"), ["", "a", "b", ""], "split empty pattern")
