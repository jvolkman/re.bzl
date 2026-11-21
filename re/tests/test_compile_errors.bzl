"""Tests that compile() rejects unsupported syntax with clear error messages."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:truth.bzl", "matching")
load("//re:re.bzl", "compile")

def _compile_subject_impl(ctx):
    compile(ctx.attr.pattern)
    return []

_compile_subject = rule(
    implementation = _compile_subject_impl,
    attrs = {
        "pattern": attr.string(),
    },
)

# name: (pattern, expected failure substring)
_CASES = {
    "positive_lookahead": ("(?=a)", "Lookarounds not supported"),
    "negative_lookahead": ("(?!a)", "Lookarounds not supported"),
    "positive_lookbehind": ("(?<=a)", "Lookbehinds not supported"),
    "negative_lookbehind": ("(?<!a)", "Lookbehinds not supported"),
    "named_backref": ("(?P<a>x)(?P=a)", "Named backreferences not supported"),
    "codepoint_too_large": (r"\x{110000}", "Codepoint too large"),
}

def _expect_failure(message):
    def impl(env, target):
        env.expect.that_target(target).failures().contains_predicate(matching.str_matches("*" + message + "*"))

    return impl

def compile_errors_test(name):
    """Creates one failing-compile test per case, and a test_suite of them.

    Args:
      name: Name of the test_suite.
    """
    tests = []
    for case, (pattern, message) in _CASES.items():
        test_name = name + "_" + case
        _compile_subject(
            name = test_name + "_subject",
            pattern = pattern,
            tags = ["manual"],
        )
        analysis_test(
            name = test_name,
            target = test_name + "_subject",
            impl = _expect_failure(message),
            expect_failure = True,
        )
        tests.append(test_name)
    native.test_suite(name = name, tests = tests)
