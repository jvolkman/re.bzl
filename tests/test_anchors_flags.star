"""
Tests for regex anchors and flags.
"""

load("tests/utils.star", "run_suite")

def run_tests_anchors_flags():
    """Runs anchors and flags tests."""
    cases = [
        # 10. Anchors
        ("^orange$", "orange", {0: "orange"}),
        ("^orange", "not orange", None),
        ("orange$", "orange juice", None),

        # 12. Word Boundaries
        ("\\bcat\\b", "cat", {0: "cat"}),
        ("\\bcat\\b", "scatter", None),
        ("\\Bcat\\B", "scatter", {0: "cat"}),
        ("\\b\\w+\\b", "Orange", {0: "Orange"}),

        # 13. Case Insensitivity
        ("(?i)orange", "OrAnGe", {0: "OrAnGe"}),
        ("(?i)[a-z]+", "ORANGE", {0: "ORANGE"}),
        ("(?i)a", "A", {0: "A"}),
        ("(?i)[^a]", "A", None),

        # 14. Multiline & Dot-All
        ("(?m)^line", "line1\nline2", {0: "line"}),
        ("(?m)^line2", "line1\nline2", {0: "line2"}),
        ("(?m)end$", "start\nend", {0: "end"}),
        ("(?s).+", "line1\nline2", {0: "line1\nline2"}),
        ("(?s).+", "line1\nline2", {0: "line1\nline2"}),
        ("(?-s).+", "line1\nline2", {0: "line1"}),

        # RE2 Compatibility: Absolute Anchors
        ("\\Aabc", "abc", {0: "abc"}),
        ("\\Aabc", "xabc", None),
        ("abc\\z", "abc", {0: "abc"}),
        ("abc\\z", "abc\n", None),

        # RE2 Compatibility: Scoped Flags
        ("(?i:a)b", "Ab", {0: "Ab"}),
        ("(?i:a)b", "AB", None),
        ("(?i:a)b", "ab", {0: "ab"}),
        ("(?i:a(?-i:b)c)", "Abc", {0: "Abc"}),
        ("(?i:a(?-i:b)c)", "AbC", {0: "AbC"}),

        # RE2 Compatibility: Ungreedy Flag
        ("(?U)a*", "aaa", {0: ""}),  # Prefer fewer
        ("(?U)a*?", "aaa", {0: "aaa"}),  # Swapped: prefer more
        ("(?U)a+", "aaa", {0: "a"}),
        ("(?U)a+?", "aaa", {0: "aaa"}),
        ("(?U)a{1,3}", "aaa", {0: "a"}),
        ("(?U:a*)b", "aaab", {0: "aaab"}),  # Scoped ungreedy

        # Stress Tests: Many Flags and Scoped Groups
        ("(?i:a(?m:b(?s:c(?U:d*))))", "Abcd", {0: "Abc"}),
        ("(?i:A(?m:B(?s:C(?U:D*))))", "abcd", {0: "abc"}),
    ]
    run_suite("Anchors & Flags Tests", cases)
