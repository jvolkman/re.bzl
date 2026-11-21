"""RE2 search and fullmatch conformance tests.

Derived from Google RE2's re2-search.txt testdata (BSD-3-Clause license), as
distributed with Go's standard library regexp package, filtered to ASCII
patterns/inputs without Unicode character property classes (\\p/\\P) or \\C.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re:re.bzl", "compile")
load("//re/private:compiler.bzl", "compile_regex", "compute_visit_limit")
load("//re/private:vm.bzl", "execute")
load("//re/tests:utils.bzl", "assert_eq")

def _spans(m, group_count):
    if m == None:
        return None
    return [m.span(i) for i in range(group_count + 1)]

def _raw_spans(regs, group_count):
    if regs == None:
        return None
    return [(regs[i * 2], regs[i * 2 + 1]) for i in range(group_count + 1)]

# Each entry is (pattern, [(text, expected_fullmatch_spans, expected_search_spans), ...]).
_CASES = [
    (
        "a",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:a)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:a)",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:a)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "a",
        [
            ("", None, None),
            ("zyzzyva", None, [(6, 7)]),
        ],
    ),
    (
        "^(?:a)$",
        [
            ("", None, None),
            ("zyzzyva", None, None),
        ],
    ),
    (
        "^(?:a)",
        [
            ("", None, None),
            ("zyzzyva", None, None),
        ],
    ),
    (
        "(?:a)$",
        [
            ("", None, None),
            ("zyzzyva", None, [(6, 7)]),
        ],
    ),
    (
        "a+",
        [
            ("", None, None),
            ("aa", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "^(?:a+)$",
        [
            ("", None, None),
            ("aa", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "^(?:a+)",
        [
            ("", None, None),
            ("aa", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "(?:a+)$",
        [
            ("", None, None),
            ("aa", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "(a+|b)+",
        [
            ("", None, None),
            ("ab", [(0, 2), (1, 2)], [(0, 2), (1, 2)]),
        ],
    ),
    (
        "^(?:(a+|b)+)$",
        [
            ("", None, None),
            ("ab", [(0, 2), (1, 2)], [(0, 2), (1, 2)]),
        ],
    ),
    (
        "^(?:(a+|b)+)",
        [
            ("", None, None),
            ("ab", [(0, 2), (1, 2)], [(0, 2), (1, 2)]),
        ],
    ),
    (
        "(?:(a+|b)+)$",
        [
            ("", None, None),
            ("ab", [(0, 2), (1, 2)], [(0, 2), (1, 2)]),
        ],
    ),
    (
        "ab|cd",
        [
            ("", None, None),
            ("xabcdx", None, [(1, 3)]),
        ],
    ),
    (
        "^(?:ab|cd)$",
        [
            ("", None, None),
            ("xabcdx", None, None),
        ],
    ),
    (
        "^(?:ab|cd)",
        [
            ("", None, None),
            ("xabcdx", None, None),
        ],
    ),
    (
        "(?:ab|cd)$",
        [
            ("", None, None),
            ("xabcdx", None, None),
        ],
    ),
    (
        "h.*od?",
        [
            ("", None, None),
            ("hello\ngoodbye\n", None, [(0, 5)]),
        ],
    ),
    (
        "^(?:h.*od?)$",
        [
            ("", None, None),
            ("hello\ngoodbye\n", None, None),
        ],
    ),
    (
        "^(?:h.*od?)",
        [
            ("", None, None),
            ("hello\ngoodbye\n", None, [(0, 5)]),
        ],
    ),
    (
        "(?:h.*od?)$",
        [
            ("", None, None),
            ("hello\ngoodbye\n", None, None),
        ],
    ),
    (
        "h.*o",
        [
            ("", None, None),
            ("hello\ngoodbye\n", None, [(0, 5)]),
        ],
    ),
    (
        "^(?:h.*o)$",
        [
            ("", None, None),
            ("hello\ngoodbye\n", None, None),
        ],
    ),
    (
        "^(?:h.*o)",
        [
            ("", None, None),
            ("hello\ngoodbye\n", None, [(0, 5)]),
        ],
    ),
    (
        "(?:h.*o)$",
        [
            ("", None, None),
            ("hello\ngoodbye\n", None, None),
        ],
    ),
    (
        "h.*o",
        [
            ("", None, None),
            ("goodbye\nhello\n", None, [(8, 13)]),
        ],
    ),
    (
        "^(?:h.*o)$",
        [
            ("", None, None),
            ("goodbye\nhello\n", None, None),
        ],
    ),
    (
        "^(?:h.*o)",
        [
            ("", None, None),
            ("goodbye\nhello\n", None, None),
        ],
    ),
    (
        "(?:h.*o)$",
        [
            ("", None, None),
            ("goodbye\nhello\n", None, None),
        ],
    ),
    (
        "h.*o",
        [
            ("", None, None),
            ("hello world", None, [(0, 8)]),
        ],
    ),
    (
        "^(?:h.*o)$",
        [
            ("", None, None),
            ("hello world", None, None),
        ],
    ),
    (
        "^(?:h.*o)",
        [
            ("", None, None),
            ("hello world", None, [(0, 8)]),
        ],
    ),
    (
        "(?:h.*o)$",
        [
            ("", None, None),
            ("hello world", None, None),
        ],
    ),
    (
        "h.*o",
        [
            ("", None, None),
            ("othello, world", None, [(2, 11)]),
        ],
    ),
    (
        "^(?:h.*o)$",
        [
            ("", None, None),
            ("othello, world", None, None),
        ],
    ),
    (
        "^(?:h.*o)",
        [
            ("", None, None),
            ("othello, world", None, None),
        ],
    ),
    (
        "(?:h.*o)$",
        [
            ("", None, None),
            ("othello, world", None, None),
        ],
    ),
    (
        "[^\\s\\S]",
        [
            ("", None, None),
            ("aaaaaaa", None, None),
        ],
    ),
    (
        "^(?:[^\\s\\S])$",
        [
            ("", None, None),
            ("aaaaaaa", None, None),
        ],
    ),
    (
        "^(?:[^\\s\\S])",
        [
            ("", None, None),
            ("aaaaaaa", None, None),
        ],
    ),
    (
        "(?:[^\\s\\S])$",
        [
            ("", None, None),
            ("aaaaaaa", None, None),
        ],
    ),
    (
        "a",
        [
            ("", None, None),
            ("aaaaaaa", None, [(0, 1)]),
        ],
    ),
    (
        "^(?:a)$",
        [
            ("", None, None),
            ("aaaaaaa", None, None),
        ],
    ),
    (
        "^(?:a)",
        [
            ("", None, None),
            ("aaaaaaa", None, [(0, 1)]),
        ],
    ),
    (
        "(?:a)$",
        [
            ("", None, None),
            ("aaaaaaa", None, [(6, 7)]),
        ],
    ),
    (
        "a*",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaaaaaa", [(0, 7)], [(0, 7)]),
        ],
    ),
    (
        "^(?:a*)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaaaaaa", [(0, 7)], [(0, 7)]),
        ],
    ),
    (
        "^(?:a*)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaaaaaa", [(0, 7)], [(0, 7)]),
        ],
    ),
    (
        "(?:a*)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaaaaaa", [(0, 7)], [(0, 7)]),
        ],
    ),
    (
        "a*",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:a*)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:a*)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:a*)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "ab|cd",
        [
            ("", None, None),
            ("xabcdx", None, [(1, 3)]),
        ],
    ),
    (
        "^(?:ab|cd)$",
        [
            ("", None, None),
            ("xabcdx", None, None),
        ],
    ),
    (
        "^(?:ab|cd)",
        [
            ("", None, None),
            ("xabcdx", None, None),
        ],
    ),
    (
        "(?:ab|cd)$",
        [
            ("", None, None),
            ("xabcdx", None, None),
        ],
    ),
    (
        "a",
        [
            ("", None, None),
            ("cab", None, [(1, 2)]),
        ],
    ),
    (
        "^(?:a)$",
        [
            ("", None, None),
            ("cab", None, None),
        ],
    ),
    (
        "^(?:a)",
        [
            ("", None, None),
            ("cab", None, None),
        ],
    ),
    (
        "(?:a)$",
        [
            ("", None, None),
            ("cab", None, None),
        ],
    ),
    (
        "a*b",
        [
            ("", None, None),
            ("cab", None, [(1, 3)]),
        ],
    ),
    (
        "^(?:a*b)$",
        [
            ("", None, None),
            ("cab", None, None),
        ],
    ),
    (
        "^(?:a*b)",
        [
            ("", None, None),
            ("cab", None, None),
        ],
    ),
    (
        "(?:a*b)$",
        [
            ("", None, None),
            ("cab", None, [(1, 3)]),
        ],
    ),
    (
        "((((((((((((((((((((x))))))))))))))))))))",
        [
            ("", None, None),
            ("x", [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)], [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)]),
        ],
    ),
    (
        "^(?:((((((((((((((((((((x)))))))))))))))))))))$",
        [
            ("", None, None),
            ("x", [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)], [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)]),
        ],
    ),
    (
        "^(?:((((((((((((((((((((x)))))))))))))))))))))",
        [
            ("", None, None),
            ("x", [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)], [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)]),
        ],
    ),
    (
        "(?:((((((((((((((((((((x)))))))))))))))))))))$",
        [
            ("", None, None),
            ("x", [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)], [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)]),
        ],
    ),
    (
        "[abcd]",
        [
            ("", None, None),
            ("xxxabcdxxx", None, [(3, 4)]),
        ],
    ),
    (
        "^(?:[abcd])$",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "^(?:[abcd])",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "(?:[abcd])$",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "[^x]",
        [
            ("", None, None),
            ("xxxabcdxxx", None, [(3, 4)]),
        ],
    ),
    (
        "^(?:[^x])$",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "^(?:[^x])",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "(?:[^x])$",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "[abcd]+",
        [
            ("", None, None),
            ("xxxabcdxxx", None, [(3, 7)]),
        ],
    ),
    (
        "^(?:[abcd]+)$",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "^(?:[abcd]+)",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "(?:[abcd]+)$",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "[^x]+",
        [
            ("", None, None),
            ("xxxabcdxxx", None, [(3, 7)]),
        ],
    ),
    (
        "^(?:[^x]+)$",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "^(?:[^x]+)",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "(?:[^x]+)$",
        [
            ("", None, None),
            ("xxxabcdxxx", None, None),
        ],
    ),
    (
        "(fo|foo)",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:(fo|foo))$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:(fo|foo))",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "(?:(fo|foo))$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "(foo|fo)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:(foo|fo))$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:(foo|fo))",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:(foo|fo))$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "aa",
        [
            ("", None, None),
            ("aA", None, None),
        ],
    ),
    (
        "^(?:aa)$",
        [
            ("", None, None),
            ("aA", None, None),
        ],
    ),
    (
        "^(?:aa)",
        [
            ("", None, None),
            ("aA", None, None),
        ],
    ),
    (
        "(?:aa)$",
        [
            ("", None, None),
            ("aA", None, None),
        ],
    ),
    (
        "a",
        [
            ("", None, None),
            ("Aa", None, [(1, 2)]),
        ],
    ),
    (
        "^(?:a)$",
        [
            ("", None, None),
            ("Aa", None, None),
        ],
    ),
    (
        "^(?:a)",
        [
            ("", None, None),
            ("Aa", None, None),
        ],
    ),
    (
        "(?:a)$",
        [
            ("", None, None),
            ("Aa", None, [(1, 2)]),
        ],
    ),
    (
        "a",
        [
            ("", None, None),
            ("A", None, None),
        ],
    ),
    (
        "^(?:a)$",
        [
            ("", None, None),
            ("A", None, None),
        ],
    ),
    (
        "^(?:a)",
        [
            ("", None, None),
            ("A", None, None),
        ],
    ),
    (
        "(?:a)$",
        [
            ("", None, None),
            ("A", None, None),
        ],
    ),
    (
        "ABC",
        [
            ("", None, None),
            ("abc", None, None),
        ],
    ),
    (
        "^(?:ABC)$",
        [
            ("", None, None),
            ("abc", None, None),
        ],
    ),
    (
        "^(?:ABC)",
        [
            ("", None, None),
            ("abc", None, None),
        ],
    ),
    (
        "(?:ABC)$",
        [
            ("", None, None),
            ("abc", None, None),
        ],
    ),
    (
        "abc",
        [
            ("", None, None),
            ("XABCY", None, None),
        ],
    ),
    (
        "^(?:abc)$",
        [
            ("", None, None),
            ("XABCY", None, None),
        ],
    ),
    (
        "^(?:abc)",
        [
            ("", None, None),
            ("XABCY", None, None),
        ],
    ),
    (
        "(?:abc)$",
        [
            ("", None, None),
            ("XABCY", None, None),
        ],
    ),
    (
        "ABC",
        [
            ("", None, None),
            ("xabcy", None, None),
        ],
    ),
    (
        "^(?:ABC)$",
        [
            ("", None, None),
            ("xabcy", None, None),
        ],
    ),
    (
        "^(?:ABC)",
        [
            ("", None, None),
            ("xabcy", None, None),
        ],
    ),
    (
        "(?:ABC)$",
        [
            ("", None, None),
            ("xabcy", None, None),
        ],
    ),
    (
        "foo|bar|[A-Z]",
        [
            ("", None, None),
            ("foo", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "^(?:foo|bar|[A-Z])$",
        [
            ("", None, None),
            ("foo", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "^(?:foo|bar|[A-Z])",
        [
            ("", None, None),
            ("foo", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "(?:foo|bar|[A-Z])$",
        [
            ("", None, None),
            ("foo", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "^(foo|bar|[A-Z])",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z]))$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z]))",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:^(foo|bar|[A-Z]))$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(foo|bar|[A-Z])$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])$)",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "(?:(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "(foo|bar|[A-Z])$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])$)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(foo|bar|[A-Z])$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "^(foo|bar|[A-Z])$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(foo|bar|[A-Z])$",
        [
            ("", None, None),
            ("bar", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("bar", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)",
        [
            ("", None, None),
            ("bar", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("bar", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(foo|bar|[A-Z])$",
        [
            ("", None, None),
            ("X", [(0, 1), (0, 1)], [(0, 1), (0, 1)]),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("X", [(0, 1), (0, 1)], [(0, 1), (0, 1)]),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)",
        [
            ("", None, None),
            ("X", [(0, 1), (0, 1)], [(0, 1), (0, 1)]),
        ],
    ),
    (
        "(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("X", [(0, 1), (0, 1)], [(0, 1), (0, 1)]),
        ],
    ),
    (
        "^(foo|bar|[A-Z])$",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "^(?:^(foo|bar|[A-Z])$)",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "(?:^(foo|bar|[A-Z])$)$",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "^(fo|foo)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:^(fo|foo)$)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:^(fo|foo)$)",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "(?:^(fo|foo)$)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(fo|foo)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^(fo|foo)$)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^(fo|foo)$)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:^(fo|foo)$)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^^(fo|foo)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:^^(fo|foo)$)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:^^(fo|foo)$)",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "(?:^^(fo|foo)$)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^^(fo|foo)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^^(fo|foo)$)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^^(fo|foo)$)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:^^(fo|foo)$)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^$$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^$$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^$$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^$$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^^$$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^^$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^^$$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^^$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^^$$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^$$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^^$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^^^^^^^^$$$$$$$$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^^^^^^^^$$$$$$$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^^^^^^^^$$$$$$$$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^^^^^^^^$$$$$$$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "^(?:^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "(?:^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, [(1, 1)]),
        ],
    ),
    (
        "^(?:$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, [(1, 1)]),
        ],
    ),
    (
        "\\bfoo\\b",
        [
            ("", None, None),
            ("nofoo foo that", None, [(6, 9)]),
        ],
    ),
    (
        "^(?:\\bfoo\\b)$",
        [
            ("", None, None),
            ("nofoo foo that", None, None),
        ],
    ),
    (
        "^(?:\\bfoo\\b)",
        [
            ("", None, None),
            ("nofoo foo that", None, None),
        ],
    ),
    (
        "(?:\\bfoo\\b)$",
        [
            ("", None, None),
            ("nofoo foo that", None, None),
        ],
    ),
    (
        "a\\b",
        [
            ("", None, None),
            ("faoa x", None, [(3, 4)]),
        ],
    ),
    (
        "^(?:a\\b)$",
        [
            ("", None, None),
            ("faoa x", None, None),
        ],
    ),
    (
        "^(?:a\\b)",
        [
            ("", None, None),
            ("faoa x", None, None),
        ],
    ),
    (
        "(?:a\\b)$",
        [
            ("", None, None),
            ("faoa x", None, None),
        ],
    ),
    (
        "\\bbar",
        [
            ("", None, None),
            ("bar x", None, [(0, 3)]),
        ],
    ),
    (
        "^(?:\\bbar)$",
        [
            ("", None, None),
            ("bar x", None, None),
        ],
    ),
    (
        "^(?:\\bbar)",
        [
            ("", None, None),
            ("bar x", None, [(0, 3)]),
        ],
    ),
    (
        "(?:\\bbar)$",
        [
            ("", None, None),
            ("bar x", None, None),
        ],
    ),
    (
        "\\bbar",
        [
            ("", None, None),
            ("foo\nbar x", None, [(4, 7)]),
        ],
    ),
    (
        "^(?:\\bbar)$",
        [
            ("", None, None),
            ("foo\nbar x", None, None),
        ],
    ),
    (
        "^(?:\\bbar)",
        [
            ("", None, None),
            ("foo\nbar x", None, None),
        ],
    ),
    (
        "(?:\\bbar)$",
        [
            ("", None, None),
            ("foo\nbar x", None, None),
        ],
    ),
    (
        "bar\\b",
        [
            ("", None, None),
            ("foobar", None, [(3, 6)]),
        ],
    ),
    (
        "^(?:bar\\b)$",
        [
            ("", None, None),
            ("foobar", None, None),
        ],
    ),
    (
        "^(?:bar\\b)",
        [
            ("", None, None),
            ("foobar", None, None),
        ],
    ),
    (
        "(?:bar\\b)$",
        [
            ("", None, None),
            ("foobar", None, [(3, 6)]),
        ],
    ),
    (
        "bar\\b",
        [
            ("", None, None),
            ("foobar\nxxx", None, [(3, 6)]),
        ],
    ),
    (
        "^(?:bar\\b)$",
        [
            ("", None, None),
            ("foobar\nxxx", None, None),
        ],
    ),
    (
        "^(?:bar\\b)",
        [
            ("", None, None),
            ("foobar\nxxx", None, None),
        ],
    ),
    (
        "(?:bar\\b)$",
        [
            ("", None, None),
            ("foobar\nxxx", None, None),
        ],
    ),
    (
        "(foo|bar|[A-Z])\\b",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])\\b)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(foo|bar|[A-Z])\\b",
        [
            ("", None, None),
            ("foo\n", None, [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])\\b)",
        [
            ("", None, None),
            ("foo\n", None, [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "\\b",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:\\b)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:\\b)",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "(?:\\b)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "\\b",
        [
            ("", None, None),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "^(?:\\b)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\b)",
        [
            ("", None, None),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "(?:\\b)$",
        [
            ("", None, None),
            ("x", None, [(1, 1)]),
        ],
    ),
    (
        "\\b(foo|bar|[A-Z])",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z]))$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z]))",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:\\b(foo|bar|[A-Z]))$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "\\b(foo|bar|[A-Z])\\b",
        [
            ("", None, None),
            ("X", [(0, 1), (0, 1)], [(0, 1), (0, 1)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("X", [(0, 1), (0, 1)], [(0, 1), (0, 1)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)",
        [
            ("", None, None),
            ("X", [(0, 1), (0, 1)], [(0, 1), (0, 1)]),
        ],
    ),
    (
        "(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("X", [(0, 1), (0, 1)], [(0, 1), (0, 1)]),
        ],
    ),
    (
        "\\b(foo|bar|[A-Z])\\b",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "\\b(foo|bar|[A-Z])\\b",
        [
            ("", None, None),
            ("bar", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("bar", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)",
        [
            ("", None, None),
            ("bar", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("bar", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "\\b(foo|bar|[A-Z])\\b",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "\\b(foo|bar|[A-Z])\\b",
        [
            ("", None, None),
            ("foo\n", None, [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)",
        [
            ("", None, None),
            ("foo\n", None, [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "\\b(foo|bar|[A-Z])\\b",
        [
            ("", None, None),
            ("ffoo bbar N x", None, [(10, 11), (10, 11)]),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("ffoo bbar N x", None, None),
        ],
    ),
    (
        "^(?:\\b(foo|bar|[A-Z])\\b)",
        [
            ("", None, None),
            ("ffoo bbar N x", None, None),
        ],
    ),
    (
        "(?:\\b(foo|bar|[A-Z])\\b)$",
        [
            ("", None, None),
            ("ffoo bbar N x", None, None),
        ],
    ),
    (
        "\\b(fo|foo)\\b",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:\\b(fo|foo)\\b)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:\\b(fo|foo)\\b)",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "(?:\\b(fo|foo)\\b)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "\\b(fo|foo)\\b",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:\\b(fo|foo)\\b)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:\\b(fo|foo)\\b)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:\\b(fo|foo)\\b)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "\\b\\b",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:\\b\\b)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:\\b\\b)",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "(?:\\b\\b)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "\\b\\b",
        [
            ("", None, None),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "^(?:\\b\\b)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\b\\b)",
        [
            ("", None, None),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "(?:\\b\\b)$",
        [
            ("", None, None),
            ("x", None, [(1, 1)]),
        ],
    ),
    (
        "\\b$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:\\b$)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:\\b$)",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "(?:\\b$)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "\\b$",
        [
            ("", None, None),
            ("x", None, [(1, 1)]),
        ],
    ),
    (
        "^(?:\\b$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\b$)",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "(?:\\b$)$",
        [
            ("", None, None),
            ("x", None, [(1, 1)]),
        ],
    ),
    (
        "\\b$",
        [
            ("", None, None),
            ("y x", None, [(3, 3)]),
        ],
    ),
    (
        "^(?:\\b$)$",
        [
            ("", None, None),
            ("y x", None, None),
        ],
    ),
    (
        "^(?:\\b$)",
        [
            ("", None, None),
            ("y x", None, None),
        ],
    ),
    (
        "(?:\\b$)$",
        [
            ("", None, None),
            ("y x", None, [(3, 3)]),
        ],
    ),
    (
        "\\b.$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\b.$)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\b.$)",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:\\b.$)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^\\b(fo|foo)\\b",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:^\\b(fo|foo)\\b)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:^\\b(fo|foo)\\b)",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "(?:^\\b(fo|foo)\\b)$",
        [
            ("", None, None),
            ("fo", [(0, 2), (0, 2)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^\\b(fo|foo)\\b",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^\\b(fo|foo)\\b)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:^\\b(fo|foo)\\b)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:^\\b(fo|foo)\\b)$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^\\b",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:^\\b)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:^\\b)",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "(?:^\\b)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^\\b",
        [
            ("", None, None),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "^(?:^\\b)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\b)",
        [
            ("", None, None),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "(?:^\\b)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^\\b\\b",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:^\\b\\b)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:^\\b\\b)",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "(?:^\\b\\b)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^\\b\\b",
        [
            ("", None, None),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "^(?:^\\b\\b)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\b\\b)",
        [
            ("", None, None),
            ("x", None, [(0, 0)]),
        ],
    ),
    (
        "(?:^\\b\\b)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^\\b$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:^\\b$)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:^\\b$)",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "(?:^\\b$)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^\\b$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\b$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\b$)",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "(?:^\\b$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^\\b.$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:^\\b.$)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:^\\b.$)",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:^\\b.$)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^\\b.\\b$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:^\\b.\\b$)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:^\\b.\\b$)",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:^\\b.\\b$)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^^^^^^^^\\b$$$$$$$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:^^^^^^^^\\b$$$$$$$)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^(?:^^^^^^^^\\b$$$$$$$)",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "(?:^^^^^^^^\\b$$$$$$$)$",
        [
            ("", None, None),
            ("", None, None),
        ],
    ),
    (
        "^^^^^^^^\\b.$$$$$$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:^^^^^^^^\\b.$$$$$$)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:^^^^^^^^\\b.$$$$$$)",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:^^^^^^^^\\b.$$$$$$)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^^^^^^^^\\b$$$$$$$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^^^^^^^\\b$$$$$$$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^^^^^^^\\b$$$$$$$)",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "(?:^^^^^^^^\\b$$$$$$$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "\\Bfoo\\B",
        [
            ("", None, None),
            ("n foo xfoox that", None, [(7, 10)]),
        ],
    ),
    (
        "^(?:\\Bfoo\\B)$",
        [
            ("", None, None),
            ("n foo xfoox that", None, None),
        ],
    ),
    (
        "^(?:\\Bfoo\\B)",
        [
            ("", None, None),
            ("n foo xfoox that", None, None),
        ],
    ),
    (
        "(?:\\Bfoo\\B)$",
        [
            ("", None, None),
            ("n foo xfoox that", None, None),
        ],
    ),
    (
        "a\\B",
        [
            ("", None, None),
            ("faoa x", None, [(1, 2)]),
        ],
    ),
    (
        "^(?:a\\B)$",
        [
            ("", None, None),
            ("faoa x", None, None),
        ],
    ),
    (
        "^(?:a\\B)",
        [
            ("", None, None),
            ("faoa x", None, None),
        ],
    ),
    (
        "(?:a\\B)$",
        [
            ("", None, None),
            ("faoa x", None, None),
        ],
    ),
    (
        "\\Bbar",
        [
            ("", None, None),
            ("bar x", None, None),
        ],
    ),
    (
        "^(?:\\Bbar)$",
        [
            ("", None, None),
            ("bar x", None, None),
        ],
    ),
    (
        "^(?:\\Bbar)",
        [
            ("", None, None),
            ("bar x", None, None),
        ],
    ),
    (
        "(?:\\Bbar)$",
        [
            ("", None, None),
            ("bar x", None, None),
        ],
    ),
    (
        "\\Bbar",
        [
            ("", None, None),
            ("foo\nbar x", None, None),
        ],
    ),
    (
        "^(?:\\Bbar)$",
        [
            ("", None, None),
            ("foo\nbar x", None, None),
        ],
    ),
    (
        "^(?:\\Bbar)",
        [
            ("", None, None),
            ("foo\nbar x", None, None),
        ],
    ),
    (
        "(?:\\Bbar)$",
        [
            ("", None, None),
            ("foo\nbar x", None, None),
        ],
    ),
    (
        "bar\\B",
        [
            ("", None, None),
            ("foobar", None, None),
        ],
    ),
    (
        "^(?:bar\\B)$",
        [
            ("", None, None),
            ("foobar", None, None),
        ],
    ),
    (
        "^(?:bar\\B)",
        [
            ("", None, None),
            ("foobar", None, None),
        ],
    ),
    (
        "(?:bar\\B)$",
        [
            ("", None, None),
            ("foobar", None, None),
        ],
    ),
    (
        "bar\\B",
        [
            ("", None, None),
            ("foobar\nxxx", None, None),
        ],
    ),
    (
        "^(?:bar\\B)$",
        [
            ("", None, None),
            ("foobar\nxxx", None, None),
        ],
    ),
    (
        "^(?:bar\\B)",
        [
            ("", None, None),
            ("foobar\nxxx", None, None),
        ],
    ),
    (
        "(?:bar\\B)$",
        [
            ("", None, None),
            ("foobar\nxxx", None, None),
        ],
    ),
    (
        "(foo|bar|[A-Z])\\B",
        [
            ("", None, None),
            ("foox", None, [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("foox", None, None),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])\\B)",
        [
            ("", None, None),
            ("foox", None, [(0, 3), (0, 3)]),
        ],
    ),
    (
        "(?:(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("foox", None, None),
        ],
    ),
    (
        "(foo|bar|[A-Z])\\B",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "^(?:(foo|bar|[A-Z])\\B)",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "(?:(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("foo\n", None, None),
        ],
    ),
    (
        "\\B",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:\\B)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "\\B",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\B)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "\\B(foo|bar|[A-Z])",
        [
            ("", None, None),
            ("foo", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z]))$",
        [
            ("", None, None),
            ("foo", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z]))",
        [
            ("", None, None),
            ("foo", None, None),
        ],
    ),
    (
        "(?:\\B(foo|bar|[A-Z]))$",
        [
            ("", None, None),
            ("foo", None, None),
        ],
    ),
    (
        "\\B(foo|bar|[A-Z])\\B",
        [
            ("", None, None),
            ("xXy", None, [(1, 2), (1, 2)]),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("xXy", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)",
        [
            ("", None, None),
            ("xXy", None, None),
        ],
    ),
    (
        "(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("xXy", None, None),
        ],
    ),
    (
        "\\B(foo|bar|[A-Z])\\B",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("XY", None, None),
        ],
    ),
    (
        "\\B(foo|bar|[A-Z])\\B",
        [
            ("", None, None),
            ("XYZ", None, [(1, 2), (1, 2)]),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("XYZ", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)",
        [
            ("", None, None),
            ("XYZ", None, None),
        ],
    ),
    (
        "(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("XYZ", None, None),
        ],
    ),
    (
        "\\B(foo|bar|[A-Z])\\B",
        [
            ("", None, None),
            ("abara", None, [(1, 4), (1, 4)]),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("abara", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)",
        [
            ("", None, None),
            ("abara", None, None),
        ],
    ),
    (
        "(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("abara", None, None),
        ],
    ),
    (
        "\\B(foo|bar|[A-Z])\\B",
        [
            ("", None, None),
            ("xfoo_", None, [(1, 4), (1, 4)]),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("xfoo_", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)",
        [
            ("", None, None),
            ("xfoo_", None, None),
        ],
    ),
    (
        "(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("xfoo_", None, None),
        ],
    ),
    (
        "\\B(foo|bar|[A-Z])\\B",
        [
            ("", None, None),
            ("xfoo\n", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("xfoo\n", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)",
        [
            ("", None, None),
            ("xfoo\n", None, None),
        ],
    ),
    (
        "(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("xfoo\n", None, None),
        ],
    ),
    (
        "\\B(foo|bar|[A-Z])\\B",
        [
            ("", None, None),
            ("foo bar vNx", None, [(9, 10), (9, 10)]),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("foo bar vNx", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|bar|[A-Z])\\B)",
        [
            ("", None, None),
            ("foo bar vNx", None, None),
        ],
    ),
    (
        "(?:\\B(foo|bar|[A-Z])\\B)$",
        [
            ("", None, None),
            ("foo bar vNx", None, None),
        ],
    ),
    (
        "\\B(fo|foo)\\B",
        [
            ("", None, None),
            ("xfoo", None, [(1, 3), (1, 3)]),
        ],
    ),
    (
        "^(?:\\B(fo|foo)\\B)$",
        [
            ("", None, None),
            ("xfoo", None, None),
        ],
    ),
    (
        "^(?:\\B(fo|foo)\\B)",
        [
            ("", None, None),
            ("xfoo", None, None),
        ],
    ),
    (
        "(?:\\B(fo|foo)\\B)$",
        [
            ("", None, None),
            ("xfoo", None, None),
        ],
    ),
    (
        "\\B(foo|fo)\\B",
        [
            ("", None, None),
            ("xfooo", None, [(1, 4), (1, 4)]),
        ],
    ),
    (
        "^(?:\\B(foo|fo)\\B)$",
        [
            ("", None, None),
            ("xfooo", None, None),
        ],
    ),
    (
        "^(?:\\B(foo|fo)\\B)",
        [
            ("", None, None),
            ("xfooo", None, None),
        ],
    ),
    (
        "(?:\\B(foo|fo)\\B)$",
        [
            ("", None, None),
            ("xfooo", None, None),
        ],
    ),
    (
        "\\B\\B",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:\\B\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:\\B\\B)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:\\B\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "\\B\\B",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\B\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\B\\B)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:\\B\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "\\B$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:\\B$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "\\B$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\B$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "\\B$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("y x", None, None),
        ],
    ),
    (
        "^(?:\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("y x", None, None),
        ],
    ),
    (
        "^(?:\\B$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("y x", None, None),
        ],
    ),
    (
        "(?:\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("y x", None, None),
        ],
    ),
    (
        "\\B.$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\B.$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:\\B.$)",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "(?:\\B.$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^\\B(fo|foo)\\B",
        [
            ("", None, None),
            ("fo", None, None),
        ],
    ),
    (
        "^(?:^\\B(fo|foo)\\B)$",
        [
            ("", None, None),
            ("fo", None, None),
        ],
    ),
    (
        "^(?:^\\B(fo|foo)\\B)",
        [
            ("", None, None),
            ("fo", None, None),
        ],
    ),
    (
        "(?:^\\B(fo|foo)\\B)$",
        [
            ("", None, None),
            ("fo", None, None),
        ],
    ),
    (
        "^\\B(fo|foo)\\B",
        [
            ("", None, None),
            ("foo", None, None),
        ],
    ),
    (
        "^(?:^\\B(fo|foo)\\B)$",
        [
            ("", None, None),
            ("foo", None, None),
        ],
    ),
    (
        "^(?:^\\B(fo|foo)\\B)",
        [
            ("", None, None),
            ("foo", None, None),
        ],
    ),
    (
        "(?:^\\B(fo|foo)\\B)$",
        [
            ("", None, None),
            ("foo", None, None),
        ],
    ),
    (
        "^\\B",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^\\B)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^\\B",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^\\B\\B",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^\\B\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^\\B\\B)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^\\B\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^\\B\\B",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B\\B)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^\\B\\B)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^\\B$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^\\B$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^\\B$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^\\B$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^\\B.$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B.$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B.$)",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "(?:^\\B.$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^\\B.\\B$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B.\\B$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^\\B.\\B$)",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "(?:^\\B.\\B$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^^^^^^^^\\B$$$$$$$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^^^^^^^^\\B$$$$$$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^^^^^^^^\\B$$$$$$$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^^^^^^^^\\B$$$$$$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^^^^^^^^\\B.$$$$$$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^^^^^^^\\B.$$$$$$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^^^^^^^\\B.$$$$$$)",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "(?:^^^^^^^^\\B.$$$$$$)$",
        [
            ("", None, None),
            ("x", None, None),
        ],
    ),
    (
        "^^^^^^^^\\B$$$$$$$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^^^^^^^\\B$$$$$$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^^^^^^^^\\B$$$$$$$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^^^^^^^^\\B$$$$$$$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
            ("x", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
            ("x>", None, [(0, 1)]),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
            ("x>", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
            ("x>", None, [(0, 1)]),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
            ("x>", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
            ("<x", None, [(1, 2)]),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
            ("<x", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
            ("<x", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
            ("<x", None, [(1, 2)]),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
            ("<x>", None, [(1, 2)]),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
            ("<x>", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
            ("<x>", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
            ("<x>", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
            ("ax", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
            ("ax", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
            ("ax", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
            ("ax", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
            ("xb", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
            ("xb", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
            ("xb", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
            ("xb", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "\\bx\\b",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\bx\\b)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:\\bx\\b)$",
        [
            ("", None, None),
        ],
    ),
    (
        "\\Bx\\B",
        [
            ("", None, None),
            ("axb", None, [(1, 2)]),
        ],
    ),
    (
        "^(?:\\Bx\\B)$",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "^(?:\\Bx\\B)",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "(?:\\Bx\\B)$",
        [
            ("", None, None),
            ("axb", None, None),
        ],
    ),
    (
        "\\Bx\\B",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\Bx\\B)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:\\Bx\\B)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:\\Bx\\B)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^$^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^$^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^$^",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^$^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:^$^)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:^$^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "$^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^(?:$^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "(?:$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("", [(0, 0)], [(0, 0)]),
        ],
    ),
    (
        "^$^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^$^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^$^",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^$^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:^$^)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:^$^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "$^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^(?:$^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "(?:$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x", None, None),
        ],
    ),
    (
        "^$^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "^(?:^$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "^(?:^$^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "(?:^$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "^$^",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "^(?:^$^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "^(?:^$^)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "(?:^$^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "$^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "^(?:$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "^(?:$^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "(?:$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\ny", None, None),
        ],
    ),
    (
        "^$^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "^(?:^$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "^(?:^$^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "(?:^$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "^$^",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "^(?:^$^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "^(?:^$^)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "(?:^$^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "$^$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "^(?:$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "^(?:$^$)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "(?:$^$)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("x\n\ny", None, None),
        ],
    ),
    (
        "^(foo\\$)$",
        [
            ("", None, None),
            ("foo$bar", None, None),
        ],
    ),
    (
        "^(?:^(foo\\$)$)$",
        [
            ("", None, None),
            ("foo$bar", None, None),
        ],
    ),
    (
        "^(?:^(foo\\$)$)",
        [
            ("", None, None),
            ("foo$bar", None, None),
        ],
    ),
    (
        "(?:^(foo\\$)$)$",
        [
            ("", None, None),
            ("foo$bar", None, None),
        ],
    ),
    (
        "(foo\\$)",
        [
            ("", None, None),
            ("foo$bar", None, [(0, 4), (0, 4)]),
        ],
    ),
    (
        "^(?:(foo\\$))$",
        [
            ("", None, None),
            ("foo$bar", None, None),
        ],
    ),
    (
        "^(?:(foo\\$))",
        [
            ("", None, None),
            ("foo$bar", None, [(0, 4), (0, 4)]),
        ],
    ),
    (
        "(?:(foo\\$))$",
        [
            ("", None, None),
            ("foo$bar", None, None),
        ],
    ),
    (
        "^...$",
        [
            ("", None, None),
            ("abc", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "^(?:^...$)$",
        [
            ("", None, None),
            ("abc", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "^(?:^...$)",
        [
            ("", None, None),
            ("abc", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "(?:^...$)$",
        [
            ("", None, None),
            ("abc", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "^...$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^...$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^...$)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:^...$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^...$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^...$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^...$)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:^...$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^...$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^...$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^...$)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:^...$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^.........$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^.........$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^.........$)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:^.........$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^...$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^...$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^...$)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:^...$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^.....$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^.....$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "^(?:^.....$)",
        [
            ("", None, None),
        ],
    ),
    (
        "(?:^.....$)$",
        [
            ("", None, None),
        ],
    ),
    (
        "\\B(fo|foo)\\B",
        [
            ("", None, None),
            ("xfooo", None, [(1, 3), (1, 3)]),
        ],
    ),
    (
        "^(?:\\B(fo|foo)\\B)$",
        [
            ("", None, None),
            ("xfooo", None, None),
        ],
    ),
    (
        "^(?:\\B(fo|foo)\\B)",
        [
            ("", None, None),
            ("xfooo", None, None),
        ],
    ),
    (
        "(?:\\B(fo|foo)\\B)$",
        [
            ("", None, None),
            ("xfooo", None, None),
        ],
    ),
    (
        "(fo|foo)",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "^(?:(fo|foo))$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "^(?:(fo|foo))",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 2), (0, 2)]),
        ],
    ),
    (
        "(?:(fo|foo))$",
        [
            ("", None, None),
            ("foo", [(0, 3), (0, 3)], [(0, 3), (0, 3)]),
        ],
    ),
    (
        "\\141",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\141)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\141)",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:\\141)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "\\060",
        [
            ("", None, None),
            ("0", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\060)$",
        [
            ("", None, None),
            ("0", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\060)",
        [
            ("", None, None),
            ("0", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:\\060)$",
        [
            ("", None, None),
            ("0", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "\\0600",
        [
            ("", None, None),
            ("00", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "^(?:\\0600)$",
        [
            ("", None, None),
            ("00", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "^(?:\\0600)",
        [
            ("", None, None),
            ("00", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "(?:\\0600)$",
        [
            ("", None, None),
            ("00", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "\\608",
        [
            ("", None, None),
            ("08", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "^(?:\\608)$",
        [
            ("", None, None),
            ("08", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "^(?:\\608)",
        [
            ("", None, None),
            ("08", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "(?:\\608)$",
        [
            ("", None, None),
            ("08", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "\\01",
        [
            ("", None, None),
            ("\001", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\01)$",
        [
            ("", None, None),
            ("\001", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\01)",
        [
            ("", None, None),
            ("\001", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:\\01)$",
        [
            ("", None, None),
            ("\001", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "\\018",
        [
            ("", None, None),
            ("\0018", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "^(?:\\018)$",
        [
            ("", None, None),
            ("\0018", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "^(?:\\018)",
        [
            ("", None, None),
            ("\0018", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "(?:\\018)$",
        [
            ("", None, None),
            ("\0018", [(0, 2)], [(0, 2)]),
        ],
    ),
    (
        "\\x{61}",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\x{61})$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\x{61})",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:\\x{61})$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "\\x61",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\x61)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\x61)",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:\\x61)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "\\x{00000061}",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\x{00000061})$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:\\x{00000061})",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:\\x{00000061})$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "[^0-9]+",
        [
            ("", None, None),
            ("abc123", None, [(0, 3)]),
        ],
    ),
    (
        "^(?:[^0-9]+)$",
        [
            ("", None, None),
            ("abc123", None, None),
        ],
    ),
    (
        "^(?:[^0-9]+)",
        [
            ("", None, None),
            ("abc123", None, [(0, 3)]),
        ],
    ),
    (
        "(?:[^0-9]+)$",
        [
            ("", None, None),
            ("abc123", None, None),
        ],
    ),
    (
        "(?i)[@-A]+",
        [
            ("", None, None),
            ("@AaB", None, [(0, 3)]),
        ],
    ),
    (
        "^(?:(?i)[@-A]+)$",
        [
            ("", None, None),
            ("@AaB", None, None),
        ],
    ),
    (
        "^(?:(?i)[@-A]+)",
        [
            ("", None, None),
            ("@AaB", None, [(0, 3)]),
        ],
    ),
    (
        "(?:(?i)[@-A]+)$",
        [
            ("", None, None),
            ("@AaB", None, None),
        ],
    ),
    (
        "(?i)[A-Z]+",
        [
            ("", None, None),
            ("aAzZ", [(0, 4)], [(0, 4)]),
        ],
    ),
    (
        "^(?:(?i)[A-Z]+)$",
        [
            ("", None, None),
            ("aAzZ", [(0, 4)], [(0, 4)]),
        ],
    ),
    (
        "^(?:(?i)[A-Z]+)",
        [
            ("", None, None),
            ("aAzZ", [(0, 4)], [(0, 4)]),
        ],
    ),
    (
        "(?:(?i)[A-Z]+)$",
        [
            ("", None, None),
            ("aAzZ", [(0, 4)], [(0, 4)]),
        ],
    ),
    (
        "(?i)[^\\\\]+",
        [
            ("", None, None),
            ("Aa\\", None, [(0, 2)]),
        ],
    ),
    (
        "^(?:(?i)[^\\\\]+)$",
        [
            ("", None, None),
            ("Aa\\", None, None),
        ],
    ),
    (
        "^(?:(?i)[^\\\\]+)",
        [
            ("", None, None),
            ("Aa\\", None, [(0, 2)]),
        ],
    ),
    (
        "(?:(?i)[^\\\\]+)$",
        [
            ("", None, None),
            ("Aa\\", None, None),
        ],
    ),
    (
        "(?i)[acegikmoqsuwy]+",
        [
            ("", None, None),
            ("acegikmoqsuwyACEGIKMOQSUWY", [(0, 26)], [(0, 26)]),
        ],
    ),
    (
        "^(?:(?i)[acegikmoqsuwy]+)$",
        [
            ("", None, None),
            ("acegikmoqsuwyACEGIKMOQSUWY", [(0, 26)], [(0, 26)]),
        ],
    ),
    (
        "^(?:(?i)[acegikmoqsuwy]+)",
        [
            ("", None, None),
            ("acegikmoqsuwyACEGIKMOQSUWY", [(0, 26)], [(0, 26)]),
        ],
    ),
    (
        "(?:(?i)[acegikmoqsuwy]+)$",
        [
            ("", None, None),
            ("acegikmoqsuwyACEGIKMOQSUWY", [(0, 26)], [(0, 26)]),
        ],
    ),
    (
        "[@-A]+",
        [
            ("", None, None),
            ("@AaB", None, [(0, 2)]),
        ],
    ),
    (
        "^(?:[@-A]+)$",
        [
            ("", None, None),
            ("@AaB", None, None),
        ],
    ),
    (
        "^(?:[@-A]+)",
        [
            ("", None, None),
            ("@AaB", None, [(0, 2)]),
        ],
    ),
    (
        "(?:[@-A]+)$",
        [
            ("", None, None),
            ("@AaB", None, None),
        ],
    ),
    (
        "[A-Z]+",
        [
            ("", None, None),
            ("aAzZ", None, [(1, 2)]),
        ],
    ),
    (
        "^(?:[A-Z]+)$",
        [
            ("", None, None),
            ("aAzZ", None, None),
        ],
    ),
    (
        "^(?:[A-Z]+)",
        [
            ("", None, None),
            ("aAzZ", None, None),
        ],
    ),
    (
        "(?:[A-Z]+)$",
        [
            ("", None, None),
            ("aAzZ", None, [(3, 4)]),
        ],
    ),
    (
        "[^\\\\]+",
        [
            ("", None, None),
            ("Aa\\", None, [(0, 2)]),
        ],
    ),
    (
        "^(?:[^\\\\]+)$",
        [
            ("", None, None),
            ("Aa\\", None, None),
        ],
    ),
    (
        "^(?:[^\\\\]+)",
        [
            ("", None, None),
            ("Aa\\", None, [(0, 2)]),
        ],
    ),
    (
        "(?:[^\\\\]+)$",
        [
            ("", None, None),
            ("Aa\\", None, None),
        ],
    ),
    (
        "[acegikmoqsuwy]+",
        [
            ("", None, None),
            ("acegikmoqsuwyACEGIKMOQSUWY", None, [(0, 13)]),
        ],
    ),
    (
        "^(?:[acegikmoqsuwy]+)$",
        [
            ("", None, None),
            ("acegikmoqsuwyACEGIKMOQSUWY", None, None),
        ],
    ),
    (
        "^(?:[acegikmoqsuwy]+)",
        [
            ("", None, None),
            ("acegikmoqsuwyACEGIKMOQSUWY", None, [(0, 13)]),
        ],
    ),
    (
        "(?:[acegikmoqsuwy]+)$",
        [
            ("", None, None),
            ("acegikmoqsuwyACEGIKMOQSUWY", None, None),
        ],
    ),
    (
        "^abc",
        [
            ("", None, None),
            ("abcdef", None, [(0, 3)]),
        ],
    ),
    (
        "^(?:^abc)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:^abc)",
        [
            ("", None, None),
            ("abcdef", None, [(0, 3)]),
        ],
    ),
    (
        "(?:^abc)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^abc",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "^(?:^abc)$",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "^(?:^abc)",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "(?:^abc)$",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "^[ay]*[bx]+c",
        [
            ("", None, None),
            ("abcdef", None, [(0, 3)]),
        ],
    ),
    (
        "^(?:^[ay]*[bx]+c)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:^[ay]*[bx]+c)",
        [
            ("", None, None),
            ("abcdef", None, [(0, 3)]),
        ],
    ),
    (
        "(?:^[ay]*[bx]+c)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^[ay]*[bx]+c",
        [
            ("", None, None),
            ("aabcdef", None, [(0, 4)]),
        ],
    ),
    (
        "^(?:^[ay]*[bx]+c)$",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "^(?:^[ay]*[bx]+c)",
        [
            ("", None, None),
            ("aabcdef", None, [(0, 4)]),
        ],
    ),
    (
        "(?:^[ay]*[bx]+c)$",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "def$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "^(?:def$)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:def$)",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "(?:def$)$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "def$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:def$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:def$)",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "(?:def$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "d[ex][fy]$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "^(?:d[ex][fy]$)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:d[ex][fy]$)",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "(?:d[ex][fy]$)$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "d[ex][fy]$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:d[ex][fy]$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:d[ex][fy]$)",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "(?:d[ex][fy]$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "[dz][ex][fy]$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "^(?:[dz][ex][fy]$)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:[dz][ex][fy]$)",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "(?:[dz][ex][fy]$)$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "[dz][ex][fy]$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:[dz][ex][fy]$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:[dz][ex][fy]$)",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "(?:[dz][ex][fy]$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "(?m)^abc",
        [
            ("", None, None),
            ("abcdef", None, [(0, 3)]),
        ],
    ),
    (
        "^(?:(?m)^abc)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:(?m)^abc)",
        [
            ("", None, None),
            ("abcdef", None, [(0, 3)]),
        ],
    ),
    (
        "(?:(?m)^abc)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "(?m)^abc",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "^(?:(?m)^abc)$",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "^(?:(?m)^abc)",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "(?:(?m)^abc)$",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "(?m)^[ay]*[bx]+c",
        [
            ("", None, None),
            ("abcdef", None, [(0, 3)]),
        ],
    ),
    (
        "^(?:(?m)^[ay]*[bx]+c)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:(?m)^[ay]*[bx]+c)",
        [
            ("", None, None),
            ("abcdef", None, [(0, 3)]),
        ],
    ),
    (
        "(?:(?m)^[ay]*[bx]+c)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "(?m)^[ay]*[bx]+c",
        [
            ("", None, None),
            ("aabcdef", None, [(0, 4)]),
        ],
    ),
    (
        "^(?:(?m)^[ay]*[bx]+c)$",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "^(?:(?m)^[ay]*[bx]+c)",
        [
            ("", None, None),
            ("aabcdef", None, [(0, 4)]),
        ],
    ),
    (
        "(?:(?m)^[ay]*[bx]+c)$",
        [
            ("", None, None),
            ("aabcdef", None, None),
        ],
    ),
    (
        "(?m)def$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "^(?:(?m)def$)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:(?m)def$)",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "(?:(?m)def$)$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "(?m)def$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:(?m)def$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:(?m)def$)",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "(?:(?m)def$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "(?m)d[ex][fy]$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "^(?:(?m)d[ex][fy]$)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:(?m)d[ex][fy]$)",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "(?:(?m)d[ex][fy]$)$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "(?m)d[ex][fy]$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:(?m)d[ex][fy]$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:(?m)d[ex][fy]$)",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "(?:(?m)d[ex][fy]$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "(?m)[dz][ex][fy]$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "^(?:(?m)[dz][ex][fy]$)$",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "^(?:(?m)[dz][ex][fy]$)",
        [
            ("", None, None),
            ("abcdef", None, None),
        ],
    ),
    (
        "(?:(?m)[dz][ex][fy]$)$",
        [
            ("", None, None),
            ("abcdef", None, [(3, 6)]),
        ],
    ),
    (
        "(?m)[dz][ex][fy]$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:(?m)[dz][ex][fy]$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^(?:(?m)[dz][ex][fy]$)",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "(?:(?m)[dz][ex][fy]$)$",
        [
            ("", None, None),
            ("abcdeff", None, None),
        ],
    ),
    (
        "^",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("a", None, [(0, 0)]),
        ],
    ),
    (
        "^(?:^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("a", None, None),
        ],
    ),
    (
        "^(?:^)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("a", None, [(0, 0)]),
        ],
    ),
    (
        "(?:^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("a", None, None),
        ],
    ),
    (
        "^^",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("a", None, [(0, 0)]),
        ],
    ),
    (
        "^(?:^^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("a", None, None),
        ],
    ),
    (
        "^(?:^^)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("a", None, [(0, 0)]),
        ],
    ),
    (
        "(?:^^)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("a", None, None),
        ],
    ),
    (
        "a",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:a)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:a)",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:a)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "ab*",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:ab*)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "^(?:ab*)",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "(?:ab*)$",
        [
            ("", None, None),
            ("a", [(0, 1)], [(0, 1)]),
        ],
    ),
    (
        "\\w*I\\w*",
        [
            ("", None, None),
            ("Inc.", None, [(0, 3)]),
        ],
    ),
    (
        "^(?:\\w*I\\w*)$",
        [
            ("", None, None),
            ("Inc.", None, None),
        ],
    ),
    (
        "^(?:\\w*I\\w*)",
        [
            ("", None, None),
            ("Inc.", None, [(0, 3)]),
        ],
    ),
    (
        "(?:\\w*I\\w*)$",
        [
            ("", None, None),
            ("Inc.", None, None),
        ],
    ),
    (
        "(?:|a)*",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaa", [(0, 3)], [(0, 0)]),
        ],
    ),
    (
        "^(?:(?:|a)*)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaa", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "^(?:(?:|a)*)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaa", [(0, 3)], [(0, 0)]),
        ],
    ),
    (
        "(?:(?:|a)*)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaa", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "(?:|a)+",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaa", [(0, 3)], [(0, 0)]),
        ],
    ),
    (
        "^(?:(?:|a)+)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaa", [(0, 3)], [(0, 3)]),
        ],
    ),
    (
        "^(?:(?:|a)+)",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaa", [(0, 3)], [(0, 0)]),
        ],
    ),
    (
        "(?:(?:|a)+)$",
        [
            ("", [(0, 0)], [(0, 0)]),
            ("aaa", [(0, 3)], [(0, 3)]),
        ],
    ),
]

def _test_re2_search(env):
    for pattern, items in _CASES:
        prog = compile(pattern)
        gc = prog.group_count
        raw_bc, _named, _gc, has_ci = compile_regex(pattern, optimize = False)
        raw_vl = compute_visit_limit(raw_bc)
        num_regs = (gc + 1) * 2
        for text, want_full, want_search in items:
            assert_eq(env, _spans(prog.fullmatch(text), gc), want_full, "RE2 fullmatch(%r, %r)" % (pattern, text))
            assert_eq(env, _spans(prog.search(text), gc), want_search, "RE2 search(%r, %r)" % (pattern, text))
            raw_full = execute(raw_bc, text, num_regs, anchored = True, has_case_insensitive = has_ci, require_end = True, visit_limit = raw_vl)
            raw_search = execute(raw_bc, text, num_regs, anchored = False, has_case_insensitive = has_ci, visit_limit = raw_vl)
            assert_eq(env, _raw_spans(raw_full, gc), want_full, "RE2 raw fullmatch(%r, %r)" % (pattern, text))
            assert_eq(env, _raw_spans(raw_search, gc), want_search, "RE2 raw search(%r, %r)" % (pattern, text))

def re2_search_test(name):
    unit_test(
        name = name,
        impl = _test_re2_search,
    )
