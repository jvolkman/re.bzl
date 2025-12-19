"""
Utility functions for the Starlark regex engine tests.
"""

load("re.bzl", "matches")

def assert_match(pattern, text, expected_match):
    """Asserts that a pattern matches the text with the expected result.

    Args:
      pattern: The regex pattern to compile and match.
      text: The input text to match against.
      expected_match: The expected match string (group 0) or None if no match is expected.
    """
    res = matches(pattern, text)
    if expected_match == None:
        if res != None:
            print("FAIL: '%s' on '%s' expected None, got %s" % (pattern, text, res))
    elif res == None:
        print("FAIL: '%s' on '%s' expected match, got None" % (pattern, text))
    elif res[0] != expected_match:
        print("FAIL: '%s' on '%s' expected '%s', got '%s'" % (pattern, text, expected_match, res[0]))

def assert_eq(actual, expected, msg):
    """Asserts that actual equals expected.

    Args:
      actual: The actual value.
      expected: The expected value.
      msg: Message to print on failure.
    """
    if actual != expected:
        print("FAIL: %s: Expected %s, Got %s" % (msg, expected, actual))

def run_suite(name, cases):
    """Runs a suite of test cases.

    Args:
      name: Name of the test suite (for logging).
      cases: List of test cases. Each case is a tuple (pattern, text, expected_groups_dict).
             expected_groups_dict is a dict of group_id/name -> matched_string, or None if no match expected.
    """
    print("--- Running %s ---" % name)
    for pattern, text, expected in cases:
        res = matches(pattern, text)
        status = "FAIL"

        if res == None and expected == None:
            status = "PASS"
        elif res != None and expected != None:
            match = True
            for k, v in expected.items():
                if k not in res or res[k] != v:
                    match = False
                    break
            if match:
                status = "PASS"

        if status == "FAIL":
            print("[FAIL] Pattern: '%s', Text: '%s'" % (pattern, text))
            print("   Expected: %s" % expected)
            print("   Got:      %s" % res)
