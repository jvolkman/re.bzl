"""Tests for Verbose mode."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//re:re.bzl", "re")

def _verbose_test_impl(ctx):
    env = unittest.begin(ctx)

    # Test whitespace skipping
    p1 = re.compile(r" a b c ", re.X)
    asserts.true(env, p1.match("abc"), "p1.match('abc') failed")
    asserts.false(env, p1.match(" a b c "), "p1.match(' a b c ') should be False")

    # Test comment skipping
    p2 = re.compile(r"""
        [+-]? # sign
        \d+   # digits
    """, re.VERBOSE)
    asserts.true(env, p2.fullmatch("+123"), "p2.fullmatch('+123') failed")
    asserts.true(env, p2.fullmatch("456"), "p2.fullmatch('456') failed")
    asserts.false(env, p2.fullmatch("+ 123"), "p2.fullmatch('+ 123') should be False")

    # Test escaped whitespace and #
    p3 = re.compile(r"a\ b\#c", re.X)
    asserts.true(env, p3.match("a b#c"), "p3.match('a b#c') failed")

    # Test inline flag (?x)
    p4 = re.compile(r"(?x) x y z ")
    asserts.true(env, p4.match("xyz"), "p4.match('xyz') failed")

    return unittest.end(env)

verbose_test = unittest.make(_verbose_test_impl)
