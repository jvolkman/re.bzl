"""
Utility functions for the Starlark regex engine tests using bazel_skylib.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lib:re.bzl", "search")

def _regex_test_impl(ctx):
    env = unittest.begin(ctx)
    name = ctx.attr.suite_name
    cases = ctx.attr.cases

    for pattern, text, expected in cases:
        res = search(pattern, text)
        if expected == None:
            asserts.equals(env, None, res, "Pattern: '%s', Text: '%s'" % (pattern, text))
        elif res == None:
            asserts.true(env, False, "Pattern: '%s', Text: '%s' expected match, got None" % (pattern, text))
        else:
            for k, v in expected.items():
                asserts.true(env, k in res, "Pattern: '%s', Text: '%s' missing group %s" % (pattern, text, k))
                if k in res:
                    asserts.equals(env, v, res[k], "Pattern: '%s', Text: '%s' group %s mismatch" % (pattern, text, k))

    return unittest.end(env)

regex_test = unittest.make(
    impl = _regex_test_impl,
    attrs = {
        "suite_name": attr.string(),
        "cases": attr.string_list_dict(),  # This won't work easily because cases are complex
    },
)

# Since cases are complex (tuples with dicts), we'll use a different approach.
# We'll define the tests in the .bzl files and export them.

def assert_match(env, pattern, text, expected_match):
    res = search(pattern, text)
    if expected_match == None:
        asserts.equals(env, None, res, "Pattern: '%s', Text: '%s' expected None" % (pattern, text))
    elif res == None:
        asserts.true(env, False, "Pattern: '%s', Text: '%s' expected match, got None" % (pattern, text))
    elif res[0] != expected_match:
        asserts.equals(env, expected_match, res[0], "Pattern: '%s', Text: '%s' mismatch" % (pattern, text))

def assert_eq(env, actual, expected, msg):
    asserts.equals(env, expected, actual, msg)

def run_suite(env, name, cases):
    for pattern, text, expected in cases:
        res = search(pattern, text)
        if expected == None:
            asserts.equals(env, None, res, "Pattern: '%s', Text: '%s' expected None" % (pattern, text))
        elif res == None:
            asserts.true(env, False, "Pattern: '%s', Text: '%s' expected match, got None" % (pattern, text))
        else:
            for k, v in expected.items():
                asserts.true(env, k in res, "Pattern: '%s', Text: '%s' missing group %s" % (pattern, text, k))
                if k in res:
                    asserts.equals(env, v, res[k], "Pattern: '%s', Text: '%s' group %s mismatch" % (pattern, text, k))
