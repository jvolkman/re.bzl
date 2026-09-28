"""
Utility functions for the Starlark regex engine tests using rules_testing.
"""

load("//re:re.bzl", "search")

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
        env.expect.that_bool(res == None).equals(True)
    elif res == None:
        # We expected a match but got None
        env.fail("Pattern: '%s', Text: '%s' expected match, got None" % (pattern, text))
    elif res.group(0) != expected_match:
        env.expect.that_str(res.group(0)).equals(expected_match)

def assert_eq(env, actual, expected, msg):
    """Asserts that two values are equal.

    Args:
      env: The test environment.
      actual: The actual value.
      expected: The expected value.
      msg: The message to display on failure.
    """
    if actual != expected:
        env.fail(msg + "\nExpected: %s\nActual: %s" % (expected, actual))

def assert_span(env, m, expected, msg):
    """Asserts that a match object has the expected span.

    Args:
      env: The test environment.
      m: The match object, or None.
      expected: The expected (start, end) tuple, or None if no match is expected.
      msg: The message to display on failure.
    """
    assert_eq(env, m.span() if m != None else None, expected, msg)

def run_suite(env, name, cases, flags = 0):
    """Runs a suite of regex tests.

    Args:
      env: The test environment.
      name: The name of the test suite.
      cases: A list of (pattern, text, expected_dict) or (pattern, text, expected_dict, flags) tuples.
      flags: Default flags to use if not specified in case.
    """
    for case in cases:
        c_flags = flags
        if len(case) == 4:
            pattern, text, expected, c_flags = case
        else:
            pattern, text, expected = case

        res = search(pattern, text, flags = c_flags)
        if expected == None:
            if res != None:
                env.fail("Suite '%s' - Pattern: '%s', Text: '%s' expected None, got match '%s'" % (name, pattern, text, res.group(0)))
        elif res == None:
            env.fail("Suite '%s' - Pattern: '%s', Text: '%s' expected match, got None" % (name, pattern, text))
        else:
            for k, v in expected.items():
                val = res.group(k)
                if val != v:
                    env.fail("Suite '%s' - Pattern: '%s', Text: '%s' group %s mismatch. Expected '%s', got '%s'" % (name, pattern, text, k, v, val))
