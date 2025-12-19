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

        # 17. Backreferences
        ("(a)\\1", "aa", {0: "aa"}),
        ("(a)\\1", "ab", None),
        ("([a-z]+) \\1", "test test", {0: "test test"}),
        ("([a-z]+) \\1", "test best", None),
        ("(?i)(a)\\1", "aA", {0: "aA"}),

        # 18. Named Backreferences
        ("(?P<x>a) (?P=x)", "a a", {0: "a a", "x": "a"}),
        ("(?P<tag><[a-z]+>).*?(?P=tag)", "<tag>content<tag>", {0: "<tag>content<tag>", "tag": "<tag>"}),
        ("(?P<tag><[a-z]+>).*?(?P=tag)", "<tag>content</tag>", None),
        ("(<[a-z]+>).*?\\1", "<tag>content<tag>", {0: "<tag>content<tag>"}),
        ("(<[a-z]+>).*?\\1", "<tag>content</tag>", None),
    ]
    run_suite("Group Tests", cases)
