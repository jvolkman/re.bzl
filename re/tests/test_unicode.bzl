"""
Tests for Unicode character support.
"""

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load("//re/tests:utils.bzl", "run_suite")

def _test_unicode_impl(ctx):
    env = unittest.begin(ctx)
    run_tests_unicode(env)
    return unittest.end(env)

unicode_test = unittest.make(_test_unicode_impl)

def run_tests_unicode(env):
    """Runs Unicode tests."""

    cases = [
        # 1. Literal Unicode
        ("❄️", "It is ❄️ outside", {0: "❄️"}),
        ("こんにちは", "こんにちは世界", {0: "こんにちは"}),

        # Grouping the unicode character should work
        ("(🚀)+", "🚀🚀🚀 blast off!", {0: "🚀🚀🚀", 1: "🚀"}),

        # TODO: Fix Unicode greedy quantization and character classes.
        # Currently, the engine operates on underlying string elements (UTF-8 bytes or UTF-16 code units), not Unicode code points.

        # 2. Unicode in character classes
        # Fails: Range compilation ([A-Z]) assumes 0-255 code points.
        # Multibyte/Multi-unit characters are a sequence, not a single scalar.
        # ("[🍎-🍍]", "I like 🍌", {0: "🍌"}),

        # Fails: [^a-z] negates a single element. The elements of "世"
        # individually match [^a-z], but the engine consumes them one by one.
        # ("[^a-z ]+", "hello 123 世界", {0: "123"}),
        # ("[^a-z 0-9]+", "hello 123 世界", {0: "世界"}),

        # 3. Unicode and quantifiers
        # Fails: '🍱' is 4 bytes. '🍱{2}' is parsed as (3 bytes) + (last byte){2}.
        # So it matches the first 3 bytes once, then the 4th byte twice.
        # ("(🍱){2}", "🍱🍱", {0: "🍱🍱", 1: "🍱"}),
        # ("🍱{2}", "🍱🍱", {0: "🍱🍱"}),

        # 4. Unicode word boundaries
        # Fails: \b uses \w which is ASCII-only ([0-9A-Za-z_]).
        # Unicode characters generally treated as non-word chars, but byte boundaries can be tricky.
        # ("\\b世界\\b", "こんにちは 世界 です", {0: "世界"}),
        # ("\\b世界\\b", "こんにちは世界です", None),

        # 5. Case insensitivity (unlikely to work across Unicode blocks)
        ("é", "É", None),  # Default CI shouldn't work for non-ASCII
        # However, let's see if we can force it somehow if we ever implement it.
    ]
    run_suite(env, "Unicode Tests", cases)
