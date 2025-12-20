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

    # Hex escapes (exercises _chr)
    assert_match("\\x41", "A", "A")
    assert_match("\\x61", "a", "a")
    assert_match("\\x30", "0", "0")
    assert_match("[\\x41-\\x44]*", "BCDCX", "BCDC")
    assert_match("\\x", "x", "x")  # Invalid hex fallback
