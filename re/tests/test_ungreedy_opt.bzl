"""
Tests for ungreedy loop optimization.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//re:re.bzl", "compile", "search")
load("//re/private:constants.bzl", "OP_UNGREEDY_LOOP")

def _test_ungreedy_opt_impl(ctx):
    env = unittest.begin(ctx)

    # 1. Functional correctness
    # a*?b matches "aaab" -> "b" at index 3? No, find(a*?b, aaab) -> "aab" at 0 doesn't make sense.
    # match(a*?b, aaab) -> "" + "b" is not possible.
    # a*?b matches "b" -> "" + "b" = "b"
    # a*?b matches "ab" -> "a" + "b" = "ab"

    cases = [
        ("a*?b", "aaab", "aaab"),
        ("a*?b", "b", "b"),
        ("[a-z]*?1", "abc1", "abc1"),
        (".*?a", "baaa", "ba"),  # Ungreedy loop stops at first 'a'
        ("a*?a", "aaaa", "a"),
    ]

    for pattern, text, expected in cases:
        m = search(pattern, text)
        asserts.true(env, m != None, "Pattern %s should match %s" % (pattern, text))
        if m:
            asserts.equals(env, expected, m.group(0))

    # 2. Bytecode inspection
    # We need to expose internal bytecode for inspection or use a debug helper.
    # Since re.compile returns a struct with 'instructions', we can check that.

    patterns_to_check = [
        "a*?b",
        "[0-9]*?x",
        "(?i)a*?b",
    ]

    for p in patterns_to_check:
        compiled = compile(p)
        found = False
        for inst in compiled.bytecode:
            if inst.op == OP_UNGREEDY_LOOP:
                found = True
                break
        asserts.true(env, found, "Pattern %s should be optimized with OP_UNGREEDY_LOOP" % p)

    return unittest.end(env)

ungreedy_opt_test = unittest.make(_test_ungreedy_opt_impl)
