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

    # RE2 Compatibility: Octal Escapes
    assert_match("\\101", "A", "A")
    assert_match("\\0", "\0", "\0")
    assert_match("\\377", "\377", "\377")
    assert_match("\\1", "\1", "\1")  # Treated as octal \001

    # RE2 Compatibility: Additional Escapes
    assert_match("\\a", "\007", "\007")
    assert_match("\\f", "\f", "\f")
    assert_match("\\v", "\v", "\v")

    # RE2 Compatibility: Hex Escapes with Braces
    assert_match("\\x{41}", "A", "A")
    assert_match("\\x{0041}", "A", "A")
    assert_match("\\x{7f}", "\177", "\177")

    # RE2 Compatibility: POSIX Character Classes
    assert_match("[[:digit:]]+", "123", "123")
    assert_match("[[:alpha:]]+", "abcABC", "abcABC")
    assert_match("[[:alnum:]]+", "a1B2", "a1B2")
    assert_match("[[:space:]]+", " \t\n", " \t\n")
    assert_match("[[:word:]]+", "abc_123", "abc_123")
    assert_match("[[:punct:]]+", "!@#", "!@#")
    assert_match("[[:lower:]]+", "abc", "abc")
    assert_match("[[:upper:]]+", "ABC", "ABC")
    assert_match("[[:ascii:]]+", "abc", "abc")
    assert_match("[[:blank:]]+", " \t", " \t")
    assert_match("[[:xdigit:]]+", "0123456789abcdefABCDEF", "0123456789abcdefABCDEF")
    assert_match("[[:^digit:]]+", "abc", "abc")
    assert_match("[[:digit:]a-z]+", "123abc", "123abc")

    # RE2 Compatibility: Quoted Literals
    assert_match("\\Q.*\\E", ".*", ".*")
    assert_match("\\Q(a|b)*\\E", "(a|b)*", "(a|b)*")
    assert_match("\\Qabc", "abc", "abc")  # Missing \E matches to end
    assert_match("a\\Q\\Eb", "ab", "ab")  # Empty \Q\E

    # Stress Tests: Large Character Class
    assert_match("[a-zA-Z0-9_.-]{5}", "aB1_-", "aB1_-")

    # Stress Tests: Many Escapes
    assert_match("\\a\\f\\n\\r\\t\\v", "\007\f\n\r\t\v", "\007\f\n\r\t\v")
