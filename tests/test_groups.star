"""
Tests for regex groups and backreferences.
"""

load("tests/utils.star", "run_suite")

def run_tests_groups():
    """Runs group tests."""
    cases = [
        # 3. Named Capture Groups
        ("(?P<fruit>orange)", "orange", {0: "orange", "fruit": "orange"}),
        ("(?P<a>\\d+)-(?P<b>\\d+)", "123-456", {0: "123-456", 1: "123", "a": "123", 2: "456", "b": "456"}),

        # 7. Non-capturing groups
        ("(?:orange)", "orange", {0: "orange"}),
        ("(?:orange)-(\\d+)", "orange-123", {0: "orange-123", 1: "123"}),

        # RE2 Compatibility: Alternative Named Group Syntax
        ("(?<name>abc)", "abc", {0: "abc", "name": "abc"}),

        # Stress Tests: Deeply Nested Groups
        ("((((((((((a))))))))))", "a", {0: "a", 1: "a", 2: "a", 3: "a", 4: "a", 5: "a", 6: "a", 7: "a", 8: "a", 9: "a", 10: "a"}),

        # Stress Tests: Many Named Groups
        ("(?P<n1>a)(?P<n2>b)(?P<n3>c)(?P<n4>d)(?P<n5>e)", "abcde", {0: "abcde", "n1": "a", "n2": "b", "n3": "c", "n4": "d", "n5": "e"}),
    ]
    run_suite("Group Tests", cases)
