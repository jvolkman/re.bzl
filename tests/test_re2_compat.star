"""
Comprehensive tests for RE2 compatibility features.
"""

load("tests/utils.star", "run_suite")

def run_tests_re2_compat():
    cases = [
        # 1. Absolute Anchors
        ("\\Aabc", "abc", {0: "abc"}),
        ("\\Aabc", "xabc", None),
        ("abc\\z", "abc", {0: "abc"}),
        ("abc\\z", "abc\n", None),

        # 2. Octal Escapes
        ("\\101", "A", {0: "A"}),
        ("\\0", "\0", {0: "\0"}),
        ("\\377", "\377", {0: "\377"}),
        ("\\1", "\1", {0: "\1"}),  # Treated as octal \001

        # 3. Scoped Flags
        ("(?i:a)b", "Ab", {0: "Ab"}),
        ("(?i:a)b", "AB", None),
        ("(?i:a)b", "ab", {0: "ab"}),
        ("(?i:a(?-i:b)c)", "Abc", {0: "Abc"}),
        ("(?i:a(?-i:b)c)", "AbC", {0: "AbC"}),

        # 4. Additional Escapes (NEW)
        ("\\a", "\007", {0: "\007"}),
        ("\\f", "\f", {0: "\f"}),
        ("\\v", "\v", {0: "\v"}),

        # 5. Hex Escapes with Braces (NEW)
        ("\\x{41}", "A", {0: "A"}),
        ("\\x{0041}", "A", {0: "A"}),
        ("\\x{7f}", "\177", {0: "\177"}),

        # 6. POSIX Character Classes (NEW)
        ("[[:digit:]]+", "123", {0: "123"}),
        ("[[:alpha:]]+", "abcABC", {0: "abcABC"}),
        ("[[:alnum:]]+", "a1B2", {0: "a1B2"}),
        ("[[:space:]]+", " \t\n", {0: " \t\n"}),
        ("[[:word:]]+", "abc_123", {0: "abc_123"}),
        ("[[:punct:]]+", "!@#", {0: "!@#"}),
        ("[[:lower:]]+", "abc", {0: "abc"}),
        ("[[:upper:]]+", "ABC", {0: "ABC"}),
        ("[[:ascii:]]+", "abc", {0: "abc"}),
        ("[[:blank:]]+", " \t", {0: " \t"}),
        ("[[:xdigit:]]+", "0123456789abcdefABCDEF", {0: "0123456789abcdefABCDEF"}),
        ("[[:^digit:]]+", "abc", {0: "abc"}),
        ("[[:digit:]a-z]+", "123abc", {0: "123abc"}),

        # 7. Alternative Named Group Syntax (NEW)
        ("(?<name>abc)", "abc", {0: "abc", "name": "abc"}),

        # 8. Ungreedy Flag (NEW)
        ("(?U)a*", "aaa", {0: ""}),  # Prefer fewer
        ("(?U)a*?", "aaa", {0: "aaa"}),  # Swapped: prefer more
        ("(?U)a+", "aaa", {0: "a"}),
        ("(?U)a+?", "aaa", {0: "aaa"}),
        ("(?U)a{1,3}", "aaa", {0: "a"}),
        ("(?U:a*)b", "aaab", {0: "aaab"}),  # Scoped ungreedy

        # 9. Quoted Literals (NEW)
        ("\\Q.*\\E", ".*", {0: ".*"}),
        ("\\Q(a|b)*\\E", "(a|b)*", {0: "(a|b)*"}),
        ("\\Qabc", "abc", {0: "abc"}),  # Missing \E matches to end
        ("a\\Q\\Eb", "ab", {0: "ab"}),  # Empty \Q\E

        # 10. Repetitions Edge Cases
        ("a{0,}", "", {0: ""}),
        ("a{0,}", "aaa", {0: "aaa"}),
        ("a{2,}", "a", None),
        ("a{2,}", "aa", {0: "aa"}),
        ("a{2,}", "aaa", {0: "aaa"}),
    ]
    run_suite("RE2 Compat Tests", cases)
