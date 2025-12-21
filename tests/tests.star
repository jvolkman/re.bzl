"""
Main test runner for the Starlark regex engine.
"""

load("tests/test_anchors_flags.star", "run_tests_anchors_flags")
load("tests/test_api.star", "run_tests_api")
load("tests/test_core.star", "run_tests_core")
load("tests/test_escape.star", "run_tests_escape")
load("tests/test_groups.star", "run_tests_groups")
load("tests/test_quantifiers.star", "run_tests_quantifiers")
load("tests/test_re2_compat.star", "run_tests_re2_compat")

def run_all_tests():
    """Runs all test suites."""
    print("=== Starting All Tests ===")
    run_tests_core()
    run_tests_quantifiers()
    run_tests_groups()
    run_tests_anchors_flags()
    run_tests_api()
    run_tests_escape()
    run_tests_re2_compat()
    print("=== All Tests Complete ===")

run_all_tests()
