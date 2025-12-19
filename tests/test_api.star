"""
Tests for the high-level API functions: findall, sub, split.
"""

load("re.bzl", "compile", "findall", "match", "search", "split", "sub")
load("tests/utils.star", "assert_eq")

def run_tests_api():
    """Runs API tests."""
    print("--- Running API Tests ---")

    # Test Compilation Reuse
    print("--- Testing Compilation Reuse ---")
    r = compile("a+")

    # Test 1: "aa"
    res1 = search(r, "aa")
    if res1 and res1[0] == "aa":
        # print("[PASS] Reuse 1: 'aa'")
        pass
    else:
        print("[FAIL] Reuse 1: Expected 'aa', Got %s" % res1)

    # Test 2: "aaaa"
    res2 = search(r, "aaaa")
    if res2 and res2[0] == "aaaa":
        # print("[PASS] Reuse 2: 'aaaa'")
        pass
    else:
        print("[FAIL] Reuse 2: Expected 'aaaa', Got %s" % res2)

    print("--- Testing match vs search ---")

    # search finds anywhere
    res = search("b", "abc")
    if res and res[0] == "b":
        pass
    else:
        print("[FAIL] search('b', 'abc'): Expected 'b', Got %s" % res)

    # match anchors at start
    res = match("b", "abc")
    if res == None:
        pass
    else:
        print("[FAIL] match('b', 'abc'): Expected None, Got %s" % res)

    # match finds at start
    res = match("a", "abc")
    if res and res[0] == "a":
        pass
    else:
        print("[FAIL] match('a', 'abc'): Expected 'a', Got %s" % res)

    print("--- Testing findall ---")

    # Test 1: Simple match
    res = findall("a+", "abaac")
    expected = ["a", "aa"]
    assert_eq(res, expected, "findall 'a+'")

    # Test 2: Groups
    res = findall("(\\w+)=(\\d+)", "a=1 b=2")
    expected = [("a", "1"), ("b", "2")]
    assert_eq(res, expected, "findall groups")

    # Test 3: Empty match
    res = findall("a*", "aba")
    expected = ["a", "", "a", ""]
    assert_eq(res, expected, "findall empty")

    print("--- Testing sub ---")

    # Test 1: Simple replacement
    res = sub("a+", "b", "abaac")
    expected = "bbbc"
    assert_eq(res, expected, "sub 'a+'->'b'")

    # Test 2: Backreferences
    res = sub("(\\w+)=(\\d+)", "\\2=\\1", "a=1 b=2")
    expected = "1=a 2=b"
    assert_eq(res, expected, "sub backref")

    # Test 3: Function replacement
    def upper_repl(match):
        return match.upper()

    res = sub("a+", upper_repl, "abaac")
    expected = "AbAAc"
    assert_eq(res, expected, "sub function")

    # Test 4: Named Backreferences
    res = sub("(?P<name>\\w+)", "Hello \\g<name>", "World")
    expected = "Hello World"
    assert_eq(res, expected, "sub named backref")

    print("--- Testing split ---")

    # Test 1: Simple split
    res = split(",", "a,b,c")
    expected = ["a", "b", "c"]
    assert_eq(res, expected, "split ','")

    # Test 2: Split with groups
    res = split("(\\W+)", "Words, words, words.")
    expected = ["Words", ", ", "words", ", ", "words", ".", ""]
    assert_eq(res, expected, "split groups")

    # Test 3: Maxsplit
    res = split(",", "a,b,c", maxsplit = 1)
    expected = ["a", "b,c"]
    assert_eq(res, expected, "split maxsplit")
