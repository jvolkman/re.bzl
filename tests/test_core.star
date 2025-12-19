"""
Tests for core regex functionality.
"""

load("tests/utils.star", "run_suite")

def run_tests_core():
    """Runs core tests."""
    cases = [
        # 4. Core functionality
        ("(orange)-(.*)", "orange-rules", {0: "orange-rules", 1: "orange", 2: "rules"}),
        ("(orange|apple)", "orange", {0: "orange", 1: "orange"}),
        ("(orange|apple)", "apple", {0: "apple", 1: "apple"}),
        ("a(b*)c", "abbbc", {0: "abbbc", 1: "bbb"}),
        ("h.llo", "hello", {0: "hello"}),
        ("(o(r(a)n)ge)", "orange", {0: "orange", 1: "orange", 2: "ran", 3: "a"}),

        # 5. Shortcuts
        ("\\d+", "123", {0: "123"}),
        ("\\w+", "Orange_123", {0: "Orange_123"}),
        ("\\s+", " \t", {0: " \t"}),
        ("[\\d]+", "456", {0: "456"}),
        ("[^\\d]+", "abc", {0: "abc"}),

        # 8. Character classes & Ranges
        ("[oa]range", "orange", {0: "orange"}),
        ("[a-z]range", "orange", {0: "orange"}),
        ("[^oa]range", "orange", None),
        ("[^oa]range", "brange", {0: "brange"}),

        # 15. Inverted Classes
        ("\\D+", "123abc456", {0: "abc"}),
        ("\\W+", "abc_123!@#", {0: "!@#"}),
        ("\\S+", "   abc   ", {0: "abc"}),
    ]
    run_suite("Core Tests", cases)
