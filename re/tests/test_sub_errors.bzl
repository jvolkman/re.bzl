"""
Tests that sub() rejects the replacement templates that Python rejects.

Each case is a target whose analysis calls sub() and must fail with the given
message, as Python raises re.error (or IndexError) for the same template.
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:truth.bzl", "matching")
load("//re:re.bzl", "sub")

def _sub_subject_impl(ctx):
    sub(ctx.attr.pattern, ctx.attr.repl, "xa")
    return []

_sub_subject = rule(
    implementation = _sub_subject_impl,
    attrs = {
        "pattern": attr.string(),
        "repl": attr.string(),
    },
)

# name: (pattern, replacement, expected failure message)
_CASES = {
    "trailing_backslash": ("(a)", "\\", "bad escape (end of pattern)"),
    "unknown_letter_escape": ("(a)", "\\q", "bad escape \\q"),
    "class_escape": ("(a)", "\\d", "bad escape \\d"),
    "missing_group_number": ("(a)", "\\2", "invalid group reference 2"),
    "missing_two_digit_group": ("(a)", "\\12", "invalid group reference 12"),
    "missing_group_g": ("(a)", "\\g<2>", "invalid group reference 2"),
    "unknown_group_name": ("(a)", "\\g<nope>", "unknown group name"),
    "unterminated_name": ("(a)", "\\g<1", "missing >, unterminated name"),
    "g_without_bracket": ("(a)", "\\g1", "missing <"),
    "empty_group_name": ("(a)", "\\g<>", "missing group name"),
    "octal_out_of_range": ("(a)", "\\400", "outside of range 0-0o377"),
}

def _expect_failure(message):
    def impl(env, target):
        env.expect.that_target(target).failures().contains_predicate(matching.str_matches("*" + message + "*"))

    return impl

def sub_template_errors_test(name):
    """Creates one failing-template test per case, and a test_suite of them.

    Args:
      name: Name of the test_suite.
    """
    tests = []
    for case, (pattern, repl, message) in _CASES.items():
        test_name = name + "_" + case
        _sub_subject(
            name = test_name + "_subject",
            pattern = pattern,
            repl = repl,
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
