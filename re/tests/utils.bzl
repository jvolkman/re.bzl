"""
Utility functions for the Starlark regex engine tests using bazel_skylib.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//re:re.bzl", "search")

def _regex_test_impl(ctx):
    env = unittest.begin(ctx)
    cases = ctx.attr.cases

    for pattern, text, expected in cases:
        res = search(pattern, text)
        if expected == None:
            asserts.equals(env, None, res, "Pattern: '%s', Text: '%s'" % (pattern, text))
        elif res == None:
            asserts.true(env, False, "Pattern: '%s', Text: '%s' expected match, got None" % (pattern, text))
        else:
            for k, v in expected.items():
                val = res.group(k)
                asserts.equals(env, v, val, "Pattern: '%s', Text: '%s' group %s mismatch" % (pattern, text, k))

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
    """Asserts that a pattern matches a text and returns the expected full match.

    Args:
      env: The test environment.
      pattern: The regex pattern.
      text: The text to search in.
      expected_match: The expected full match (group 0), or None if no match expected.
    """
    res = search(pattern, text)
    if expected_match == None:
        asserts.equals(env, None, res, "Pattern: '%s', Text: '%s' expected None" % (pattern, text))
    elif res == None:
        asserts.true(env, False, "Pattern: '%s', Text: '%s' expected match, got None" % (pattern, text))
    elif res.group(0) != expected_match:
        asserts.equals(env, expected_match, res.group(0), "Pattern: '%s', Text: '%s' mismatch" % (pattern, text))

def assert_eq(env, actual, expected, msg):
    """Asserts that two values are equal.

    Args:
      env: The test environment.
      actual: The actual value.
      expected: The expected value.
      msg: The message to display on failure.
    """
    asserts.equals(env, expected, actual, msg)

def run_suite(env, name, cases):
    """Runs a suite of regex tests.

    Args:
      env: The test environment.
      name: The name of the test suite.
      cases: A list of (pattern, text, expected_dict) tuples.
    """
    for pattern, text, expected in cases:
        res = search(pattern, text)
        if expected == None:
            asserts.equals(env, None, res, "Pattern: '%s', Text: '%s' expected None" % (pattern, text))
        elif res == None:
            asserts.true(env, False, "Pattern: '%s', Text: '%s' expected match, got None" % (pattern, text))
        else:
            for k, v in expected.items():
                val = res.group(k)
                asserts.equals(env, v, val, "Pattern: '%s', Text: '%s' group %s mismatch" % (pattern, text, k))
