"""
Tests for escaping special characters.
"""

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//re/tests:utils.bzl", "assert_match")

def _test_escape_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_escape(env)
    return unittest.end(env)

escape_test = unittest.make(_test_escape_impl)

def run_tests_escape(env):
    """Runs escape tests.

    Args:
      env: The test environment.
    """

    # 1. Standard Escapes
    assert_match(env, "\\.", ".", ".")
    assert_match(env, "\\*", "*", "*")
    assert_match(env, "\\+", "+", "+")
    assert_match(env, "\\?", "?", "?")
    assert_match(env, "\\\\", "\\", "\\")

    # RE2 Compatibility: Octal Escapes
    assert_match(env, "\\141", "a", "a")
    assert_match(env, "\\000", "\0", "\0")

    # RE2 Compatibility: Additional Escapes
    assert_match(env, "\\a", "\a", "\a")
    assert_match(env, "\\f", "\f", "\f")
    assert_match(env, "\\v", "\v", "\v")

    # RE2 Compatibility: Hex Escapes with Braces
    assert_match(env, "\\x{61}", "a", "a")

    # RE2 Compatibility: POSIX Character Classes
    class_tests = [
        ("alnum", "a1", "a"),
        ("alpha", "a1", "a"),
        ("ascii", "\177", "\177"),
        ("blank", " \t", " "),
        ("cntrl", "\001", "\001"),
        ("digit", "5", "5"),
        ("graph", "!", "!"),
        ("lower", "g", "g"),
        ("print", " ", " "),
        ("punct", ".", "."),
        ("space", "\n", "\n"),
        ("upper", "G", "G"),
        ("word", "_", "_"),
        ("xdigit", "f", "f"),
    ]
    for cls, text, expected in class_tests:
        assert_match(env, "[[:%s:]]" % cls, text, expected)

        # Note: [[:^alpha:]] search on "a1" should match "1"
        if cls == "alpha":
            assert_match(env, "[[:^alpha:]]", "a1", "1")
        else:
            assert_match(env, "[[:^%s:]]" % cls, text, None)

    # Character Class Edge Cases
    assert_match(env, "[-abc]", "-", "-")  # Hyphen at start
    assert_match(env, "[abc-]", "-", "-")  # Hyphen at end
    assert_match(env, "[]abc]", "]", "]")  # Bracket at start
    assert_match(env, "[^]abc]", "x", "x")  # Negated bracket at start
    assert_match(env, "[^]abc]", "]", None)
    assert_match(env, "[a\\-z]", "-", "-")  # Escaped hyphen
    assert_match(env, "[a\\-z]", "a", "a")
    assert_match(env, "[a-c-e]", "b", "b")  # Multiple ranges/hyphens
    assert_match(env, "[a-c-e]", "-", "-")
    assert_match(env, "[[:digit:]a-fA-F]", "e", "e")  # Mixed POSIX and literal
    assert_match(env, "[a-f[:digit:]A-F]", "5", "5")
    assert_match(env, "[^-a-c]", "d", "d")  # Negated start hyphen
    assert_match(env, "[^-a-c]", "-", None)

    # RE2 Compatibility: Quoted Literals
    assert_match(env, "\\Q.*+\\E", ".*+", ".*+")
    assert_match(env, "\\Q.*+\\E", "abc", None)

    # Stress Tests: Large Character Classes
    assert_match(env, "[a-zA-Z0-9_]+", "aZ0_", "aZ0_")

    # Stress Tests: Many Escapes
    assert_match(env, "\\n\\r\\t\\a\\f\\v", "\n\r\t\a\f\v", "\n\r\t\a\f\v")

    # Unicode Escapes (Starlark JSON trick)
    # 1. BMP \uXXXX
    assert_match(env, "\\u263A", "☺", "☺")

    # 2. Supplementary \UXXXXXXXX
    assert_match(env, "\\U0001F600", "😀", "😀")

    # 3. Mixed Escape types
    assert_match(env, "Hello \\u263A", "Hello ☺", "Hello ☺")
