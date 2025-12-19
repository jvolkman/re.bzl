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
    ]
    run_suite("Anchors & Flags Tests", cases)
