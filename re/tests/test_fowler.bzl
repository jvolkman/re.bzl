"""AT&T Research (Glenn Fowler) testregex conformance tests.

Derived from basic.dat, nullsubexpr.dat, and repetition.dat (AT&T Research
permissive license, as distributed with Go's standard library regexp package).

Expected spans match RE2 leftmost-first semantics, except for the 37 nullable-
loop submatch cases (e.g. `(a*)*` on `"a"`, `X(.?){0,}Y` on `"X1234567Y"`) where
re.bzl intentionally follows CPython's empty-iteration capture semantics (see
re/tests/test_quantifiers.bzl).
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re:re.bzl", "IGNORECASE", "compile")
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

# Each entry is (source, pattern, flags, text, expected_search_spans).
_CASES = [
    ("basic.dat:3", "abracadabra$", 0, "abracadabracadabra", [(7, 18)]),
    ("basic.dat:4", "a...b", 0, "abababbb", [(2, 7)]),
    ("basic.dat:5", "XXXXXX", 0, "..XXXXXX", [(2, 8)]),
    ("basic.dat:6", "\\)", 0, "()", [(1, 2)]),
    ("basic.dat:7", "a]", 0, "a]a", [(0, 2)]),
    ("basic.dat:9", "\\}", 0, "}", [(0, 1)]),
    ("basic.dat:10", "\\]", 0, "]", [(0, 1)]),
    ("basic.dat:12", "]", 0, "]", [(0, 1)]),
    ("basic.dat:15", "^a", 0, "ax", [(0, 1)]),
    ("basic.dat:16", "\\^a", 0, "a^a", [(1, 3)]),
    ("basic.dat:17", "a\\^", 0, "a^", [(0, 2)]),
    ("basic.dat:18", "a$", 0, "aa", [(1, 2)]),
    ("basic.dat:19", "a\\$", 0, "a$", [(0, 2)]),
    ("basic.dat:20", "^$", 0, "", [(0, 0)]),
    ("basic.dat:21", "$^", 0, "", [(0, 0)]),
    ("basic.dat:22", "a($)", 0, "aa", [(1, 2), (2, 2)]),
    ("basic.dat:23", "a*(^a)", 0, "aa", [(0, 1), (0, 1)]),
    ("basic.dat:24", "(..)*(...)*", 0, "a", [(0, 0), (-1, -1), (-1, -1)]),
    ("basic.dat:25", "(..)*(...)*", 0, "abcd", [(0, 4), (2, 4), (-1, -1)]),
    ("basic.dat:26", "(ab|a)(bc|c)", 0, "abc", [(0, 3), (0, 2), (2, 3)]),
    ("basic.dat:27", "(ab)c|abc", 0, "abc", [(0, 3), (0, 2)]),
    ("basic.dat:28", "a{0}b", 0, "ab", [(1, 2)]),
    ("basic.dat:29", "(a*)(b?)(b+)b{3}", 0, "aaabbbbbbb", [(0, 10), (0, 3), (3, 4), (4, 7)]),
    ("basic.dat:30", "(a*)(b{0,1})(b{1,})b{3}", 0, "aaabbbbbbb", [(0, 10), (0, 3), (3, 4), (4, 7)]),
    ("basic.dat:32", "((a|a)|a)", 0, "a", [(0, 1), (0, 1), (0, 1)]),
    ("basic.dat:33", "(a*)(a|aa)", 0, "aaaa", [(0, 4), (0, 3), (3, 4)]),
    ("basic.dat:34", "a*(a.|aa)", 0, "aaaa", [(0, 4), (2, 4)]),
    ("basic.dat:35", "a(b)|c(d)|a(e)f", 0, "aef", [(0, 3), (-1, -1), (-1, -1), (1, 2)]),
    ("basic.dat:36", "(a|b)?.*", 0, "b", [(0, 1), (0, 1)]),
    ("basic.dat:37", "(a|b)c|a(b|c)", 0, "ac", [(0, 2), (0, 1), (-1, -1)]),
    ("basic.dat:38", "(a|b)c|a(b|c)", 0, "ab", [(0, 2), (-1, -1), (1, 2)]),
    ("basic.dat:39", "(a|b)*c|(a|ab)*c", 0, "abc", [(0, 3), (1, 2), (-1, -1)]),
    ("basic.dat:40", "(a|b)*c|(a|ab)*c", 0, "xc", [(1, 2), (-1, -1), (-1, -1)]),
    ("basic.dat:41", "(.a|.b).*|.*(.a|.b)", 0, "xa", [(0, 2), (0, 2), (-1, -1)]),
    ("basic.dat:42", "a?(ab|ba)ab", 0, "abab", [(0, 4), (0, 2)]),
    ("basic.dat:43", "a?(ac{0}b|ba)ab", 0, "abab", [(0, 4), (0, 2)]),
    ("basic.dat:44", "ab|abab", 0, "abbabab", [(0, 2)]),
    ("basic.dat:45", "aba|bab|bba", 0, "baaabbbaba", [(5, 8)]),
    ("basic.dat:46", "aba|bab", 0, "baaabbbaba", [(6, 9)]),
    ("basic.dat:47", "(aa|aaa)*|(a|aaaaa)", 0, "aa", [(0, 2), (0, 2), (-1, -1)]),
    ("basic.dat:48", "(a.|.a.)*|(a|.a...)", 0, "aa", [(0, 2), (0, 2), (-1, -1)]),
    ("basic.dat:49", "ab|a", 0, "xabc", [(1, 3)]),
    ("basic.dat:50", "ab|a", 0, "xxabc", [(2, 4)]),
    ("basic.dat:51", "(Ab|cD)*", IGNORECASE, "aBcD", [(0, 4), (2, 4)]),
    ("basic.dat:52", "[^-]", 0, "--a", [(2, 3)]),
    ("basic.dat:53", "[a-]*", 0, "--a", [(0, 3)]),
    ("basic.dat:54", "[a-m-]*", 0, "--amoma--", [(0, 4)]),
    ("basic.dat:55", ":::1:::0:|:::1:1:0:", 0, ":::0:::1:::1:::0:", [(8, 17)]),
    ("basic.dat:56", ":::1:::0:|:::1:1:1:", 0, ":::0:::1:::1:::0:", [(8, 17)]),
    ("basic.dat:57", "[[:upper:]]", 0, "A", [(0, 1)]),
    ("basic.dat:58", "[[:lower:]]+", 0, "`az{", [(1, 3)]),
    ("basic.dat:59", "[[:upper:]]+", 0, "@AZ[", [(1, 3)]),
    ("basic.dat:65", "\n", 0, "\n", [(0, 1)]),
    ("basic.dat:67", "[^a]", 0, "\n", [(0, 1)]),
    ("basic.dat:68", "\na", 0, "\na", [(0, 2)]),
    ("basic.dat:69", "(a)(b)(c)", 0, "abc", [(0, 3), (0, 1), (1, 2), (2, 3)]),
    ("basic.dat:70", "xxx", 0, "xxx", [(0, 3)]),
    ("basic.dat:71", "(^|[ (,;])((([Ff]eb[^ ]* *|0*2/|\\* */?)0*[6-7]))([^0-9]|$)", 0, "feb 6,", [(0, 6), (0, 0), (0, 5), (0, 5), (0, 4), (5, 6)]),
    ("basic.dat:72", "(^|[ (,;])((([Ff]eb[^ ]* *|0*2/|\\* */?)0*[6-7]))([^0-9]|$)", 0, "2/7", [(0, 3), (0, 0), (0, 3), (0, 3), (0, 2), (3, 3)]),
    ("basic.dat:73", "(^|[ (,;])((([Ff]eb[^ ]* *|0*2/|\\* */?)0*[6-7]))([^0-9]|$)", 0, "feb 1,Feb 6", [(5, 11), (5, 6), (6, 11), (6, 11), (6, 10), (11, 11)]),
    ("basic.dat:74", "((((((((((((((((((((((((((((((x))))))))))))))))))))))))))))))", 0, "x", [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)]),
    ("basic.dat:75", "((((((((((((((((((((((((((((((x))))))))))))))))))))))))))))))*", 0, "xx", [(0, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2), (1, 2)]),
    ("basic.dat:76", "a?(ab|ba)*", 0, "ababababababababababababababababababababababababababababababababababababababababa", [(0, 81), (79, 81)]),
    ("basic.dat:77", "abaa|abbaa|abbbaa|abbbbaa", 0, "ababbabbbabbbabbbbabbbbaa", [(18, 25)]),
    ("basic.dat:78", "abaa|abbaa|abbbaa|abbbbaa", 0, "ababbabbbabbbabbbbabaa", [(18, 22)]),
    ("basic.dat:79", "aaac|aabc|abac|abbc|baac|babc|bbac|bbbc", 0, "baaabbbabac", [(7, 11)]),
    ("basic.dat:81", "aaaa|bbbb|cccc|ddddd|eeeeee|fffffff|gggg|hhhh|iiiii|jjjjj|kkkkk|llll", 0, "XaaaXbbbXcccXdddXeeeXfffXgggXhhhXiiiXjjjXkkkXlllXcbaXaaaa", [(53, 57)]),
    ("basic.dat:83", "a*a*a*a*a*b", 0, "aaaaaaaaab", [(0, 10)]),
    ("basic.dat:84", "^", 0, "", [(0, 0)]),
    ("basic.dat:85", "$", 0, "", [(0, 0)]),
    ("basic.dat:86", "^$", 0, "", [(0, 0)]),
    ("basic.dat:87", "^a$", 0, "a", [(0, 1)]),
    ("basic.dat:88", "abc", 0, "abc", [(0, 3)]),
    ("basic.dat:89", "abc", 0, "xabcy", [(1, 4)]),
    ("basic.dat:90", "abc", 0, "ababc", [(2, 5)]),
    ("basic.dat:91", "ab*c", 0, "abc", [(0, 3)]),
    ("basic.dat:92", "ab*bc", 0, "abc", [(0, 3)]),
    ("basic.dat:93", "ab*bc", 0, "abbc", [(0, 4)]),
    ("basic.dat:94", "ab*bc", 0, "abbbbc", [(0, 6)]),
    ("basic.dat:95", "ab+bc", 0, "abbc", [(0, 4)]),
    ("basic.dat:96", "ab+bc", 0, "abbbbc", [(0, 6)]),
    ("basic.dat:97", "ab?bc", 0, "abbc", [(0, 4)]),
    ("basic.dat:98", "ab?bc", 0, "abc", [(0, 3)]),
    ("basic.dat:99", "ab?c", 0, "abc", [(0, 3)]),
    ("basic.dat:100", "^abc$", 0, "abc", [(0, 3)]),
    ("basic.dat:101", "^abc", 0, "abcc", [(0, 3)]),
    ("basic.dat:102", "abc$", 0, "aabc", [(1, 4)]),
    ("basic.dat:103", "^", 0, "abc", [(0, 0)]),
    ("basic.dat:104", "$", 0, "abc", [(3, 3)]),
    ("basic.dat:105", "a.c", 0, "abc", [(0, 3)]),
    ("basic.dat:106", "a.c", 0, "axc", [(0, 3)]),
    ("basic.dat:107", "a.*c", 0, "axyzc", [(0, 5)]),
    ("basic.dat:108", "a[bc]d", 0, "abd", [(0, 3)]),
    ("basic.dat:109", "a[b-d]e", 0, "ace", [(0, 3)]),
    ("basic.dat:110", "a[b-d]", 0, "aac", [(1, 3)]),
    ("basic.dat:111", "a[-b]", 0, "a-", [(0, 2)]),
    ("basic.dat:112", "a[b-]", 0, "a-", [(0, 2)]),
    ("basic.dat:113", "a]", 0, "a]", [(0, 2)]),
    ("basic.dat:114", "a[]]b", 0, "a]b", [(0, 3)]),
    ("basic.dat:115", "a[^bc]d", 0, "aed", [(0, 3)]),
    ("basic.dat:116", "a[^-b]c", 0, "adc", [(0, 3)]),
    ("basic.dat:117", "a[^]b]c", 0, "adc", [(0, 3)]),
    ("basic.dat:118", "ab|cd", 0, "abc", [(0, 2)]),
    ("basic.dat:119", "ab|cd", 0, "abcd", [(0, 2)]),
    ("basic.dat:120", "a\\(b", 0, "a(b", [(0, 3)]),
    ("basic.dat:121", "a\\(*b", 0, "ab", [(0, 2)]),
    ("basic.dat:122", "a\\(*b", 0, "a((b", [(0, 4)]),
    ("basic.dat:123", "((a))", 0, "abc", [(0, 1), (0, 1), (0, 1)]),
    ("basic.dat:124", "(a)b(c)", 0, "abc", [(0, 3), (0, 1), (2, 3)]),
    ("basic.dat:125", "a+b+c", 0, "aabbabc", [(4, 7)]),
    ("basic.dat:126", "a*", 0, "aaa", [(0, 3)]),
    ("basic.dat:127", "(a*)*", 0, "-", [(0, 0), (0, 0)]),
    ("basic.dat:128", "(a*)+", 0, "-", [(0, 0), (0, 0)]),
    ("basic.dat:129", "(a*|b)*", 0, "-", [(0, 0), (0, 0)]),
    ("basic.dat:130", "(a+|b)*", 0, "ab", [(0, 2), (1, 2)]),
    ("basic.dat:131", "(a+|b)+", 0, "ab", [(0, 2), (1, 2)]),
    ("basic.dat:132", "(a+|b)?", 0, "ab", [(0, 1), (0, 1)]),
    ("basic.dat:133", "[^ab]*", 0, "cde", [(0, 3)]),
    ("basic.dat:134", "(^)*", 0, "-", [(0, 0), (0, 0)]),
    ("basic.dat:135", "a*", 0, "", [(0, 0)]),
    ("basic.dat:136", "([abc])*d", 0, "abbbcd", [(0, 6), (4, 5)]),
    ("basic.dat:137", "([abc])*bcd", 0, "abcd", [(0, 4), (0, 1)]),
    ("basic.dat:138", "a|b|c|d|e", 0, "e", [(0, 1)]),
    ("basic.dat:139", "(a|b|c|d|e)f", 0, "ef", [(0, 2), (0, 1)]),
    ("basic.dat:140", "((a*|b))*", 0, "-", [(0, 0), (0, 0), (0, 0)]),
    ("basic.dat:141", "abcd*efg", 0, "abcdefg", [(0, 7)]),
    ("basic.dat:142", "ab*", 0, "xabyabbbz", [(1, 3)]),
    ("basic.dat:143", "ab*", 0, "xayabbbz", [(1, 2)]),
    ("basic.dat:144", "(ab|cd)e", 0, "abcde", [(2, 5), (2, 4)]),
    ("basic.dat:145", "[abhgefdc]ij", 0, "hij", [(0, 3)]),
    ("basic.dat:146", "(a|b)c*d", 0, "abcd", [(1, 4), (1, 2)]),
    ("basic.dat:147", "(ab|ab*)bc", 0, "abc", [(0, 3), (0, 1)]),
    ("basic.dat:148", "a([bc]*)c*", 0, "abc", [(0, 3), (1, 3)]),
    ("basic.dat:149", "a([bc]*)(c*d)", 0, "abcd", [(0, 4), (1, 3), (3, 4)]),
    ("basic.dat:150", "a([bc]+)(c*d)", 0, "abcd", [(0, 4), (1, 3), (3, 4)]),
    ("basic.dat:151", "a([bc]*)(c+d)", 0, "abcd", [(0, 4), (1, 2), (2, 4)]),
    ("basic.dat:152", "a[bcd]*dcdcde", 0, "adcdcde", [(0, 7)]),
    ("basic.dat:153", "(ab|a)b*c", 0, "abc", [(0, 3), (0, 2)]),
    ("basic.dat:154", "((a)(b)c)(d)", 0, "abcd", [(0, 4), (0, 3), (0, 1), (1, 2), (3, 4)]),
    ("basic.dat:155", "[A-Za-z_][A-Za-z0-9_]*", 0, "alpha", [(0, 5)]),
    ("basic.dat:156", "^a(bc+|b[eh])g|.h$", 0, "abh", [(1, 3), (-1, -1)]),
    ("basic.dat:157", "(bc+d$|ef*g.|h?i(j|k))", 0, "effgz", [(0, 5), (0, 5), (-1, -1)]),
    ("basic.dat:158", "(bc+d$|ef*g.|h?i(j|k))", 0, "ij", [(0, 2), (0, 2), (1, 2)]),
    ("basic.dat:159", "(bc+d$|ef*g.|h?i(j|k))", 0, "reffgz", [(1, 6), (1, 6), (-1, -1)]),
    ("basic.dat:160", "(((((((((a)))))))))", 0, "a", [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)]),
    ("basic.dat:161", "multiple words", 0, "multiple words yeah", [(0, 14)]),
    ("basic.dat:162", "(.*)c(.*)", 0, "abcde", [(0, 5), (0, 2), (3, 5)]),
    ("basic.dat:163", "abcd", 0, "abcd", [(0, 4)]),
    ("basic.dat:164", "a(bc)d", 0, "abcd", [(0, 4), (1, 3)]),
    ("basic.dat:165", "a[\001-\003]?c", 0, "a\002c", [(0, 3)]),
    ("basic.dat:166", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Qaddafi", [(0, 15), (-1, -1), (10, 12)]),
    ("basic.dat:167", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Mo'ammar Gadhafi", [(0, 16), (-1, -1), (11, 13)]),
    ("basic.dat:168", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Kaddafi", [(0, 15), (-1, -1), (10, 12)]),
    ("basic.dat:169", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Qadhafi", [(0, 15), (-1, -1), (10, 12)]),
    ("basic.dat:170", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Gadafi", [(0, 14), (-1, -1), (10, 11)]),
    ("basic.dat:171", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Mu'ammar Qadafi", [(0, 15), (-1, -1), (11, 12)]),
    ("basic.dat:172", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Moamar Gaddafi", [(0, 14), (-1, -1), (9, 11)]),
    ("basic.dat:173", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Mu'ammar Qadhdhafi", [(0, 18), (-1, -1), (13, 15)]),
    ("basic.dat:174", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Khaddafi", [(0, 16), (-1, -1), (11, 13)]),
    ("basic.dat:175", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Ghaddafy", [(0, 16), (-1, -1), (11, 13)]),
    ("basic.dat:176", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Ghadafi", [(0, 15), (-1, -1), (11, 12)]),
    ("basic.dat:177", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Ghaddafi", [(0, 16), (-1, -1), (11, 13)]),
    ("basic.dat:178", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muamar Kaddafi", [(0, 14), (-1, -1), (9, 11)]),
    ("basic.dat:179", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Quathafi", [(0, 16), (-1, -1), (11, 13)]),
    ("basic.dat:180", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Muammar Gheddafi", [(0, 16), (-1, -1), (11, 13)]),
    ("basic.dat:181", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Moammar Khadafy", [(0, 15), (-1, -1), (11, 12)]),
    ("basic.dat:182", "M[ou]'?am+[ae]r .*([AEae]l[- ])?[GKQ]h?[aeu]+([dtz][dhz]?)+af[iy]", 0, "Moammar Qudhafi", [(0, 15), (-1, -1), (10, 12)]),
    ("basic.dat:183", "a+(b|c)*d+", 0, "aabcdd", [(0, 6), (3, 4)]),
    ("basic.dat:184", "^.+$", 0, "vivi", [(0, 4)]),
    ("basic.dat:185", "^(.+)$", 0, "vivi", [(0, 4), (0, 4)]),
    ("basic.dat:186", "^([^!.]+).att.com!(.+)$", 0, "gryphon.att.com!eby", [(0, 19), (0, 7), (16, 19)]),
    ("basic.dat:187", "^([^!]+!)?([^!]+)$", 0, "bas", [(0, 3), (-1, -1), (0, 3)]),
    ("basic.dat:188", "^([^!]+!)?([^!]+)$", 0, "bar!bas", [(0, 7), (0, 4), (4, 7)]),
    ("basic.dat:189", "^([^!]+!)?([^!]+)$", 0, "foo!bas", [(0, 7), (0, 4), (4, 7)]),
    ("basic.dat:190", "^.+!([^!]+!)([^!]+)$", 0, "foo!bar!bas", [(0, 11), (4, 8), (8, 11)]),
    ("basic.dat:191", "((foo)|(bar))!bas", 0, "bar!bas", [(0, 7), (0, 3), (-1, -1), (0, 3)]),
    ("basic.dat:192", "((foo)|(bar))!bas", 0, "foo!bar!bas", [(4, 11), (4, 7), (-1, -1), (4, 7)]),
    ("basic.dat:193", "((foo)|(bar))!bas", 0, "foo!bas", [(0, 7), (0, 3), (0, 3), (-1, -1)]),
    ("basic.dat:194", "((foo)|bar)!bas", 0, "bar!bas", [(0, 7), (0, 3), (-1, -1)]),
    ("basic.dat:195", "((foo)|bar)!bas", 0, "foo!bar!bas", [(4, 11), (4, 7), (-1, -1)]),
    ("basic.dat:196", "((foo)|bar)!bas", 0, "foo!bas", [(0, 7), (0, 3), (0, 3)]),
    ("basic.dat:197", "(foo|(bar))!bas", 0, "bar!bas", [(0, 7), (0, 3), (0, 3)]),
    ("basic.dat:198", "(foo|(bar))!bas", 0, "foo!bar!bas", [(4, 11), (4, 7), (4, 7)]),
    ("basic.dat:199", "(foo|(bar))!bas", 0, "foo!bas", [(0, 7), (0, 3), (-1, -1)]),
    ("basic.dat:200", "(foo|bar)!bas", 0, "bar!bas", [(0, 7), (0, 3)]),
    ("basic.dat:201", "(foo|bar)!bas", 0, "foo!bar!bas", [(4, 11), (4, 7)]),
    ("basic.dat:202", "(foo|bar)!bas", 0, "foo!bas", [(0, 7), (0, 3)]),
    ("basic.dat:203", "^(([^!]+!)?([^!]+)|.+!([^!]+!)([^!]+))$", 0, "foo!bar!bas", [(0, 11), (0, 11), (-1, -1), (-1, -1), (4, 8), (8, 11)]),
    ("basic.dat:204", "^([^!]+!)?([^!]+)$|^.+!([^!]+!)([^!]+)$", 0, "bas", [(0, 3), (-1, -1), (0, 3), (-1, -1), (-1, -1)]),
    ("basic.dat:205", "^([^!]+!)?([^!]+)$|^.+!([^!]+!)([^!]+)$", 0, "bar!bas", [(0, 7), (0, 4), (4, 7), (-1, -1), (-1, -1)]),
    ("basic.dat:206", "^([^!]+!)?([^!]+)$|^.+!([^!]+!)([^!]+)$", 0, "foo!bar!bas", [(0, 11), (-1, -1), (-1, -1), (4, 8), (8, 11)]),
    ("basic.dat:207", "^([^!]+!)?([^!]+)$|^.+!([^!]+!)([^!]+)$", 0, "foo!bas", [(0, 7), (0, 4), (4, 7), (-1, -1), (-1, -1)]),
    ("basic.dat:208", "^(([^!]+!)?([^!]+)|.+!([^!]+!)([^!]+))$", 0, "bas", [(0, 3), (0, 3), (-1, -1), (0, 3), (-1, -1), (-1, -1)]),
    ("basic.dat:209", "^(([^!]+!)?([^!]+)|.+!([^!]+!)([^!]+))$", 0, "bar!bas", [(0, 7), (0, 7), (0, 4), (4, 7), (-1, -1), (-1, -1)]),
    ("basic.dat:210", "^(([^!]+!)?([^!]+)|.+!([^!]+!)([^!]+))$", 0, "foo!bar!bas", [(0, 11), (0, 11), (-1, -1), (-1, -1), (4, 8), (8, 11)]),
    ("basic.dat:211", "^(([^!]+!)?([^!]+)|.+!([^!]+!)([^!]+))$", 0, "foo!bas", [(0, 7), (0, 7), (0, 4), (4, 7), (-1, -1), (-1, -1)]),
    ("basic.dat:212", ".*(/XXX).*", 0, "/XXX", [(0, 4), (0, 4)]),
    ("basic.dat:213", ".*(\\\\XXX).*", 0, "\\XXX", [(0, 4), (0, 4)]),
    ("basic.dat:214", "\\\\XXX", 0, "\\XXX", [(0, 4)]),
    ("basic.dat:215", ".*(/000).*", 0, "/000", [(0, 4), (0, 4)]),
    ("basic.dat:216", ".*(\\\\000).*", 0, "\\000", [(0, 4), (0, 4)]),
    ("basic.dat:217", "\\\\000", 0, "\\000", [(0, 4)]),
    ("nullsubexpr.dat:3", "(a*)*", 0, "a", [(0, 1), (1, 1)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:4", "(a*)*", 0, "x", [(0, 0), (0, 0)]),
    ("nullsubexpr.dat:5", "(a*)*", 0, "aaaaaa", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:6", "(a*)*", 0, "aaaaaax", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:7", "(a*)+", 0, "a", [(0, 1), (1, 1)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:8", "(a*)+", 0, "x", [(0, 0), (0, 0)]),
    ("nullsubexpr.dat:9", "(a*)+", 0, "aaaaaa", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:10", "(a*)+", 0, "aaaaaax", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:11", "(a+)*", 0, "a", [(0, 1), (0, 1)]),
    ("nullsubexpr.dat:12", "(a+)*", 0, "x", [(0, 0), (-1, -1)]),
    ("nullsubexpr.dat:13", "(a+)*", 0, "aaaaaa", [(0, 6), (0, 6)]),
    ("nullsubexpr.dat:14", "(a+)*", 0, "aaaaaax", [(0, 6), (0, 6)]),
    ("nullsubexpr.dat:15", "(a+)+", 0, "a", [(0, 1), (0, 1)]),
    ("nullsubexpr.dat:16", "(a+)+", 0, "x", None),
    ("nullsubexpr.dat:17", "(a+)+", 0, "aaaaaa", [(0, 6), (0, 6)]),
    ("nullsubexpr.dat:18", "(a+)+", 0, "aaaaaax", [(0, 6), (0, 6)]),
    ("nullsubexpr.dat:20", "([a]*)*", 0, "a", [(0, 1), (1, 1)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:21", "([a]*)*", 0, "x", [(0, 0), (0, 0)]),
    ("nullsubexpr.dat:22", "([a]*)*", 0, "aaaaaa", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:23", "([a]*)*", 0, "aaaaaax", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:24", "([a]*)+", 0, "a", [(0, 1), (1, 1)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:25", "([a]*)+", 0, "x", [(0, 0), (0, 0)]),
    ("nullsubexpr.dat:26", "([a]*)+", 0, "aaaaaa", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:27", "([a]*)+", 0, "aaaaaax", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:28", "([^b]*)*", 0, "a", [(0, 1), (1, 1)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:29", "([^b]*)*", 0, "b", [(0, 0), (0, 0)]),
    ("nullsubexpr.dat:30", "([^b]*)*", 0, "aaaaaa", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:31", "([^b]*)*", 0, "aaaaaab", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:32", "([ab]*)*", 0, "a", [(0, 1), (1, 1)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:33", "([ab]*)*", 0, "aaaaaa", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:34", "([ab]*)*", 0, "ababab", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:35", "([ab]*)*", 0, "bababa", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:36", "([ab]*)*", 0, "b", [(0, 1), (1, 1)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:37", "([ab]*)*", 0, "bbbbbb", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:38", "([ab]*)*", 0, "aaaabcde", [(0, 5), (5, 5)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:39", "([^a]*)*", 0, "b", [(0, 1), (1, 1)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:40", "([^a]*)*", 0, "bbbbbb", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:41", "([^a]*)*", 0, "aaaaaa", [(0, 0), (0, 0)]),
    ("nullsubexpr.dat:42", "([^ab]*)*", 0, "ccccxx", [(0, 6), (6, 6)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:43", "([^ab]*)*", 0, "ababab", [(0, 0), (0, 0)]),
    ("nullsubexpr.dat:45", "((z)+|a)*", 0, "zabcde", [(0, 2), (1, 2), (0, 1)]),
    ("nullsubexpr.dat:63", "(a*)*(x)", 0, "x", [(0, 1), (0, 0), (0, 1)]),
    ("nullsubexpr.dat:64", "(a*)*(x)", 0, "ax", [(0, 2), (1, 1), (1, 2)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:65", "(a*)*(x)", 0, "axa", [(0, 2), (1, 1), (1, 2)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:67", "(a*)+(x)", 0, "x", [(0, 1), (0, 0), (0, 1)]),
    ("nullsubexpr.dat:68", "(a*)+(x)", 0, "ax", [(0, 2), (1, 1), (1, 2)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:69", "(a*)+(x)", 0, "axa", [(0, 2), (1, 1), (1, 2)]),  # CPython empty-iteration capture
    ("nullsubexpr.dat:71", "(a*){2}(x)", 0, "x", [(0, 1), (0, 0), (0, 1)]),
    ("nullsubexpr.dat:72", "(a*){2}(x)", 0, "ax", [(0, 2), (1, 1), (1, 2)]),
    ("nullsubexpr.dat:73", "(a*){2}(x)", 0, "axa", [(0, 2), (1, 1), (1, 2)]),
    ("repetition.dat:10", "((..)|(.))", 0, "", None),
    ("repetition.dat:11", "((..)|(.))((..)|(.))", 0, "", None),
    ("repetition.dat:12", "((..)|(.))((..)|(.))((..)|(.))", 0, "", None),
    ("repetition.dat:14", "((..)|(.)){1}", 0, "", None),
    ("repetition.dat:15", "((..)|(.)){2}", 0, "", None),
    ("repetition.dat:16", "((..)|(.)){3}", 0, "", None),
    ("repetition.dat:18", "((..)|(.))*", 0, "", [(0, 0), (-1, -1), (-1, -1), (-1, -1)]),
    ("repetition.dat:20", "((..)|(.))", 0, "a", [(0, 1), (0, 1), (-1, -1), (0, 1)]),
    ("repetition.dat:21", "((..)|(.))((..)|(.))", 0, "a", None),
    ("repetition.dat:22", "((..)|(.))((..)|(.))((..)|(.))", 0, "a", None),
    ("repetition.dat:24", "((..)|(.)){1}", 0, "a", [(0, 1), (0, 1), (-1, -1), (0, 1)]),
    ("repetition.dat:25", "((..)|(.)){2}", 0, "a", None),
    ("repetition.dat:26", "((..)|(.)){3}", 0, "a", None),
    ("repetition.dat:28", "((..)|(.))*", 0, "a", [(0, 1), (0, 1), (-1, -1), (0, 1)]),
    ("repetition.dat:30", "((..)|(.))", 0, "aa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:31", "((..)|(.))((..)|(.))", 0, "aa", [(0, 2), (0, 1), (-1, -1), (0, 1), (1, 2), (-1, -1), (1, 2)]),
    ("repetition.dat:32", "((..)|(.))((..)|(.))((..)|(.))", 0, "aa", None),
    ("repetition.dat:34", "((..)|(.)){1}", 0, "aa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:35", "((..)|(.)){2}", 0, "aa", [(0, 2), (1, 2), (-1, -1), (1, 2)]),
    ("repetition.dat:36", "((..)|(.)){3}", 0, "aa", None),
    ("repetition.dat:38", "((..)|(.))*", 0, "aa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:40", "((..)|(.))", 0, "aaa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:41", "((..)|(.))((..)|(.))", 0, "aaa", [(0, 3), (0, 2), (0, 2), (-1, -1), (2, 3), (-1, -1), (2, 3)]),
    ("repetition.dat:42", "((..)|(.))((..)|(.))((..)|(.))", 0, "aaa", [(0, 3), (0, 1), (-1, -1), (0, 1), (1, 2), (-1, -1), (1, 2), (2, 3), (-1, -1), (2, 3)]),
    ("repetition.dat:44", "((..)|(.)){1}", 0, "aaa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:46", "((..)|(.)){2}", 0, "aaa", [(0, 3), (2, 3), (0, 2), (2, 3)]),
    ("repetition.dat:47", "((..)|(.)){3}", 0, "aaa", [(0, 3), (2, 3), (-1, -1), (2, 3)]),
    ("repetition.dat:50", "((..)|(.))*", 0, "aaa", [(0, 3), (2, 3), (0, 2), (2, 3)]),
    ("repetition.dat:52", "((..)|(.))", 0, "aaaa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:53", "((..)|(.))((..)|(.))", 0, "aaaa", [(0, 4), (0, 2), (0, 2), (-1, -1), (2, 4), (2, 4), (-1, -1)]),
    ("repetition.dat:54", "((..)|(.))((..)|(.))((..)|(.))", 0, "aaaa", [(0, 4), (0, 2), (0, 2), (-1, -1), (2, 3), (-1, -1), (2, 3), (3, 4), (-1, -1), (3, 4)]),
    ("repetition.dat:56", "((..)|(.)){1}", 0, "aaaa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:57", "((..)|(.)){2}", 0, "aaaa", [(0, 4), (2, 4), (2, 4), (-1, -1)]),
    ("repetition.dat:59", "((..)|(.)){3}", 0, "aaaa", [(0, 4), (3, 4), (0, 2), (3, 4)]),
    ("repetition.dat:61", "((..)|(.))*", 0, "aaaa", [(0, 4), (2, 4), (2, 4), (-1, -1)]),
    ("repetition.dat:63", "((..)|(.))", 0, "aaaaa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:64", "((..)|(.))((..)|(.))", 0, "aaaaa", [(0, 4), (0, 2), (0, 2), (-1, -1), (2, 4), (2, 4), (-1, -1)]),
    ("repetition.dat:65", "((..)|(.))((..)|(.))((..)|(.))", 0, "aaaaa", [(0, 5), (0, 2), (0, 2), (-1, -1), (2, 4), (2, 4), (-1, -1), (4, 5), (-1, -1), (4, 5)]),
    ("repetition.dat:67", "((..)|(.)){1}", 0, "aaaaa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:68", "((..)|(.)){2}", 0, "aaaaa", [(0, 4), (2, 4), (2, 4), (-1, -1)]),
    ("repetition.dat:70", "((..)|(.)){3}", 0, "aaaaa", [(0, 5), (4, 5), (2, 4), (4, 5)]),
    ("repetition.dat:73", "((..)|(.))*", 0, "aaaaa", [(0, 5), (4, 5), (2, 4), (4, 5)]),
    ("repetition.dat:75", "((..)|(.))", 0, "aaaaaa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:76", "((..)|(.))((..)|(.))", 0, "aaaaaa", [(0, 4), (0, 2), (0, 2), (-1, -1), (2, 4), (2, 4), (-1, -1)]),
    ("repetition.dat:77", "((..)|(.))((..)|(.))((..)|(.))", 0, "aaaaaa", [(0, 6), (0, 2), (0, 2), (-1, -1), (2, 4), (2, 4), (-1, -1), (4, 6), (4, 6), (-1, -1)]),
    ("repetition.dat:79", "((..)|(.)){1}", 0, "aaaaaa", [(0, 2), (0, 2), (0, 2), (-1, -1)]),
    ("repetition.dat:80", "((..)|(.)){2}", 0, "aaaaaa", [(0, 4), (2, 4), (2, 4), (-1, -1)]),
    ("repetition.dat:81", "((..)|(.)){3}", 0, "aaaaaa", [(0, 6), (4, 6), (4, 6), (-1, -1)]),
    ("repetition.dat:83", "((..)|(.))*", 0, "aaaaaa", [(0, 6), (4, 6), (4, 6), (-1, -1)]),
    ("repetition.dat:90", "X(.?){0,}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),  # CPython empty-iteration capture
    ("repetition.dat:91", "X(.?){1,}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),  # CPython empty-iteration capture
    ("repetition.dat:92", "X(.?){2,}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),  # CPython empty-iteration capture
    ("repetition.dat:93", "X(.?){3,}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),  # CPython empty-iteration capture
    ("repetition.dat:94", "X(.?){4,}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),  # CPython empty-iteration capture
    ("repetition.dat:95", "X(.?){5,}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),  # CPython empty-iteration capture
    ("repetition.dat:96", "X(.?){6,}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),  # CPython empty-iteration capture
    ("repetition.dat:97", "X(.?){7,}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),  # CPython empty-iteration capture
    ("repetition.dat:98", "X(.?){8,}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:100", "X(.?){0,8}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:102", "X(.?){1,8}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:104", "X(.?){2,8}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:106", "X(.?){3,8}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:108", "X(.?){4,8}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:110", "X(.?){5,8}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:112", "X(.?){6,8}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:114", "X(.?){7,8}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:115", "X(.?){8,8}Y", 0, "X1234567Y", [(0, 9), (8, 8)]),
    ("repetition.dat:126", "(a|ab|c|bcd){0,}(d*)", 0, "ababcd", [(0, 1), (0, 1), (1, 1)]),
    ("repetition.dat:127", "(a|ab|c|bcd){1,}(d*)", 0, "ababcd", [(0, 1), (0, 1), (1, 1)]),
    ("repetition.dat:128", "(a|ab|c|bcd){2,}(d*)", 0, "ababcd", [(0, 6), (3, 6), (6, 6)]),
    ("repetition.dat:129", "(a|ab|c|bcd){3,}(d*)", 0, "ababcd", [(0, 6), (3, 6), (6, 6)]),
    ("repetition.dat:130", "(a|ab|c|bcd){4,}(d*)", 0, "ababcd", None),
    ("repetition.dat:131", "(a|ab|c|bcd){0,10}(d*)", 0, "ababcd", [(0, 1), (0, 1), (1, 1)]),
    ("repetition.dat:132", "(a|ab|c|bcd){1,10}(d*)", 0, "ababcd", [(0, 1), (0, 1), (1, 1)]),
    ("repetition.dat:133", "(a|ab|c|bcd){2,10}(d*)", 0, "ababcd", [(0, 6), (3, 6), (6, 6)]),
    ("repetition.dat:134", "(a|ab|c|bcd){3,10}(d*)", 0, "ababcd", [(0, 6), (3, 6), (6, 6)]),
    ("repetition.dat:135", "(a|ab|c|bcd){4,10}(d*)", 0, "ababcd", None),
    ("repetition.dat:136", "(a|ab|c|bcd)*(d*)", 0, "ababcd", [(0, 1), (0, 1), (1, 1)]),
    ("repetition.dat:137", "(a|ab|c|bcd)+(d*)", 0, "ababcd", [(0, 1), (0, 1), (1, 1)]),
    ("repetition.dat:143", "(ab|a|c|bcd){0,}(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
    ("repetition.dat:145", "(ab|a|c|bcd){1,}(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
    ("repetition.dat:147", "(ab|a|c|bcd){2,}(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
    ("repetition.dat:149", "(ab|a|c|bcd){3,}(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
    ("repetition.dat:150", "(ab|a|c|bcd){4,}(d*)", 0, "ababcd", None),
    ("repetition.dat:152", "(ab|a|c|bcd){0,10}(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
    ("repetition.dat:154", "(ab|a|c|bcd){1,10}(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
    ("repetition.dat:156", "(ab|a|c|bcd){2,10}(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
    ("repetition.dat:158", "(ab|a|c|bcd){3,10}(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
    ("repetition.dat:159", "(ab|a|c|bcd){4,10}(d*)", 0, "ababcd", None),
    ("repetition.dat:161", "(ab|a|c|bcd)*(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
    ("repetition.dat:163", "(ab|a|c|bcd)+(d*)", 0, "ababcd", [(0, 6), (4, 5), (5, 6)]),
]

def _test_fowler(env):
    for src, pattern, flags, text, want in _CASES:
        prog = compile(pattern, flags = flags)
        gc = prog.group_count
        assert_eq(env, _spans(prog.search(text), gc), want, "Fowler %s search(%r, %r)" % (src, pattern, text))
        raw_bc, _named, _gc, has_ci = compile_regex(pattern, flags = flags, optimize = False)
        raw_vl = compute_visit_limit(raw_bc)
        raw_regs = execute(raw_bc, text, (gc + 1) * 2, anchored = False, has_case_insensitive = has_ci, visit_limit = raw_vl)
        assert_eq(env, _raw_spans(raw_regs, gc), want, "Fowler %s raw search(%r, %r)" % (src, pattern, text))

def fowler_test(name):
    unit_test(
        name = name,
        impl = _test_fowler,
    )
