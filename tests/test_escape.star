"""
Tests for escaping special characters.
"""

load("tests/utils.star", "assert_match")

def run_tests_escape():
    """Runs escape tests."""
    print("--- Verifying Escaping Support ---")

    # Escaped special characters
    assert_match("a\\*b", "a*b", "a*b")
    assert_match("a\\?b", "a?b", "a?b")
    assert_match("a\\+b", "a+b", "a+b")
    assert_match("a\\.b", "a.b", "a.b")
    assert_match("a\\^b", "a^b", "a^b")
    assert_match("a\\$b", "a$b", "a$b")
    assert_match("a\\|b", "a|b", "a|b")
    assert_match("a\\(b", "a(b", "a(b")
    assert_match("a\\)b", "a)b", "a)b")
    assert_match("a\\[b", "a[b", "a[b")

    assert_match("a\\]b", "a]b", "a]b")  # ] usually treated as literal if not closing a set, but good to check
    assert_match("a\\{b", "a{b", "a{b")

    # Escaped backslash
    assert_match("a\\\\b", "a\\b", "a\\b")

    # Escaping in character classes
    assert_match("[a\\-z]", "-", "-")  # Literal -
    assert_match("[\\]]", "]", "]")  # Literal ]
