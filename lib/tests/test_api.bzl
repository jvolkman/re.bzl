"""
Tests for the high-level API functions: findall, sub, split.
"""

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//lib:re.bzl", "compile", "findall", "fullmatch", "match", "search", "split", "sub")
load("//lib/tests:utils.bzl", "assert_eq")

def _test_api_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_api(env)
    return unittest.end(env)

api_test = unittest.make(_test_api_impl)

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

    # \d+ DOES have an opt struct (it's a simple set)
    m11 = search(r"\d+", "123")
    assert_eq(env, m11.re.opt != None, True, "simple set should have opt struct")
