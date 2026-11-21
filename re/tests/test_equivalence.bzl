"""Fast-path vs. pure unoptimized NFA equivalence (self-oracle) tests.

Every case is evaluated through both the full optimized engine (bytecode loop
peepholes, `opt` fast paths, `first_skip`, `alt_dispatch`, `match_end`, and
`scanner` inline rules) and the raw unoptimized Thompson NFA (`compile_regex(...,
optimize=False)` + `execute()`), asserting identical spans, capture groups, and
`lastindex`.
"""

load("@rules_testing//lib:unit_test.bzl", "unit_test")
load("//re:re.bzl", "DOTALL", "IGNORECASE", "UNGREEDY", "compile", "scanner")
load("//re/private:compiler.bzl", "compile_regex", "compute_visit_limit")
load("//re/private:vm.bzl", "execute")
load("//re/tests:utils.bzl", "assert_eq")

def _clamp(text, pos, endpos):
    n = len(text)
    if endpos == None or endpos > n:
        endpos = n
    elif endpos < 0:
        endpos = 0
    if pos < 0 or pos > n:
        pos = 0 if pos < 0 else n
    return pos, endpos

# buildifier: disable=list-append
def _regs_from_match(m, group_count):
    if m == None:
        return None
    res = []
    for i in range(group_count + 1):
        s, e = m.span(i)
        res += [s, e]
    res += [-1 if m.lastindex == None else m.lastindex]
    return res

def _check_pattern_equiv(env, pattern, flags, text, pos = 0, endpos = None):
    prog = compile(pattern, flags = flags)
    raw_bc, _named, group_count, has_ci = compile_regex(pattern, flags = flags, optimize = False)
    raw_vl = compute_visit_limit(raw_bc)
    num_regs = (group_count + 1) * 2
    c_pos, c_end = _clamp(text, pos, endpos)
    label = "pat=%r flags=%d text=%r pos=%d endpos=%r" % (pattern, flags, text, pos, endpos)

    # 1. search()
    opt_s = _regs_from_match(prog.search(text, pos, endpos), group_count)
    raw_s = execute(raw_bc, text, num_regs, start_index = c_pos, end_index = c_end, anchored = False, has_case_insensitive = has_ci, visit_limit = raw_vl)
    assert_eq(env, opt_s, raw_s, "search equiv: " + label)

    # 2. match() and match_end()
    opt_m = _regs_from_match(prog.match(text, pos, endpos), group_count)
    raw_m = execute(raw_bc, text, num_regs, start_index = c_pos, end_index = c_end, anchored = True, has_case_insensitive = has_ci, visit_limit = raw_vl)
    assert_eq(env, opt_m, raw_m, "match equiv: " + label)
    opt_me = prog.match_end(text, pos, endpos)
    raw_me = raw_m[1] if raw_m != None else None
    assert_eq(env, opt_me, raw_me, "match_end equiv: " + label)

    # 3. fullmatch()
    opt_f = _regs_from_match(prog.fullmatch(text, pos, endpos), group_count)
    raw_f = execute(raw_bc, text, num_regs, start_index = c_pos, end_index = c_end, anchored = True, has_case_insensitive = has_ci, require_end = True, visit_limit = raw_vl)
    assert_eq(env, opt_f, raw_f, "fullmatch equiv: " + label)

def _raw_scanner_match(raw_rules, text, pos, endpos):
    for tag, bc, group_count, has_ci, vl in raw_rules:
        regs = execute(bc, text, (group_count + 1) * 2, start_index = pos, end_index = endpos, anchored = True, has_case_insensitive = has_ci, visit_limit = vl)
        if regs != None:
            return (tag, regs[1])
    return None

# buildifier: disable=list-append
def _raw_scanner_scan(raw_rules, text, pos, endpos):
    tokens = []
    for _ in range(endpos - pos):
        if pos >= endpos:
            break
        hit = _raw_scanner_match(raw_rules, text, pos, endpos)
        if hit == None or hit[1] <= pos:
            break
        tag, end = hit
        if tag != None:
            tokens += [(tag, pos, end)]
        pos = end
    return tokens, pos

# buildifier: disable=list-append
def _check_scanner_equiv(env, rules, flags, text, pos = 0, endpos = None, label = "", raw_specs = None):
    sc = scanner(rules, flags = flags)
    raw_rules = []
    specs = raw_specs if raw_specs != None else [(tag, pat, flags) for tag, pat in rules]
    for tag, pat_str, pat_flags in specs:
        bc, _n, gc, ci = compile_regex(pat_str, flags = pat_flags, optimize = False)
        raw_rules += [(tag, bc, gc, ci, compute_visit_limit(bc))]

    c_pos, c_end = _clamp(text, pos, endpos)
    assert_eq(
        env,
        sc.match(text, pos, endpos),
        _raw_scanner_match(raw_rules, text, c_pos, c_end),
        "scanner.match equiv (%s) pos=%d endpos=%r" % (label, pos, endpos),
    )
    assert_eq(
        env,
        sc.scan(text, pos, endpos),
        _raw_scanner_scan(raw_rules, text, c_pos, c_end),
        "scanner.scan equiv (%s) pos=%d endpos=%r" % (label, pos, endpos),
    )

def _test_equivalence(env):
    # Matrix of patterns exercising every optimizer path:
    # - literals, CI literals, mixed scoped CI
    # - positive/negated sets, OP_GREEDY_LOOP, OP_UNGREEDY_LOOP, OP_NEG_GREEDY_LOOP
    # - dot / DOTALL, suffix search, anchored start/end, multiline, word boundaries
    # - top-level alternation dispatch (simple, overlapping first chars, captures, inner groups)
    # - nested nullable loops
    patterns = [
        # Literals & sets
        ("abc", 0),
        ("abc", IGNORECASE),
        ("a(?i:b)c", 0),
        ("[a-z]+", 0),
        ("[a-z]+?", 0),
        ("[a-z]+", UNGREEDY),
        (r"\d+", 0),
        (r"\D+", 0),
        (r"\S+", 0),
        (r"\s+", 0),
        # Prefix + loop + suffix (overlapping & disjoint, CS & CI)
        ("a*b", 0),
        ("a*?b", 0),
        ("[ab][bc]*c", 0),
        ("[ab][bc]*c$", 0),
        ("(?i)x[a-c]*d", 0),
        ("(?i:[a-c]*)B", 0),
        ("[A-C]*(?i:b)", 0),
        ("(?i:[ab])[ab]*b$", 0),
        ("^foo[0-9]+bar$", 0),
        ("^a|b$", 0),
        ("(?m)^[a-z]+$", 0),
        ("(?m)[^a]*$", 0),
        # Negated sets & dot loops
        (r"#[^\n]*", 0),
        (r"#.*", 0),
        (r"#.*", DOTALL),
        (r"[^\"\\]+", 0),
        (r"\"(?:[^\"\\]|\\.)*\"", 0),
        (r"([^:]*):(.*)", 0),
        (r"(?i)[^a]*a", 0),
        (r"[^a]*a$", 0),
        (r"a([^x]*)b", 0),
        (r".", 0),
        (r".", DOTALL),
        (r"[^a]", 0),
        (r"[[:^digit:]]+", 0),
        # Top-level alternations (alt_dispatch)
        ("a|ab|abc", 0),
        ("ab|a", 0),
        ("(?P<K>key)|(?P<ID>[a-z]+)|(?P<NUM>[0-9]+)", 0),
        ("(?P<A>a(b))|(?P<C>a(c))|(?P<D>d+)", 0),
        ("(?i)true|false|null", 0),
        (r"(?P<WS>[ \t]+)|(?P<COMMENT>#[^\n]*)|(?P<KEY>[A-Za-z_][A-Za-z0-9_\-]*)|(?P<EQ>=)|(?P<STR>\"(?:[^\"\\]|\\.)*\")|(?P<NUM>[+-]?\d+(?:\.\d+)?)", 0),
        (r"true\b|false\b|[a-z]+", 0),
        (r"^abc|def|[^a]z", 0),
        # Nullable / complex loops
        ("(a*)*", 0),
        ("(|a){1,3}$", 0),
        ("(?:ab|cd)+e", 0),
        (r"\bfoo\b", 0),
    ]

    texts = [
        "",
        "a",
        "ab",
        "abc",
        "aBc",
        "aaab",
        "ccbc",
        "xABbB",
        "x # hi\nnext",
        "key:value\nnext",
        "\"hello \\\"world\\\"\"",
        "key = true # comment\nfoo123 = \"bar\"",
        "trueish false null",
        "foo123bar",
        "   abc\t世界\n123  ",
        "ab ac ddd",
        "aaxb ab",
        "\n",
    ]

    for pat, fl in patterns:
        for txt in texts:
            _check_pattern_equiv(env, pat, fl, txt)

    # Also test non-default pos/endpos slices across representative patterns.
    slice_patterns = [
        ("abc", 0),
        ("[ab][bc]*c", 0),
        ("[ab][bc]*c$", 0),
        (r"#[^\n]*", 0),
        (r"\D+", 0),
        ("(?P<A>a(b))|(?P<C>a(c))|(?P<D>d+)", 0),
        ("(?P<K>key)|(?P<ID>[a-z]+)|(?P<NUM>[0-9]+)", 0),
        ("^abc|def", 0),
        ("a|ab", 0),
    ]
    slice_text = "xx# hi\nabc key123 ac ddd ccbc"
    slices = [
        (0, None),
        (2, 10),
        (7, 15),
        (11, 20),
        (0, 0),
        (len(slice_text), None),
        (-5, 100),
        (10, 5),
    ]
    for pat, fl in slice_patterns:
        for pos, endpos in slices:
            _check_pattern_equiv(env, pat, fl, slice_text, pos, endpos)

    # Scanner equivalence tests.
    toml_rules = [
        (None, r"[ \t]+"),
        ("NL", r"\r?\n"),
        ("COMMENT", r"#[^\n]*"),
        ("LBRACK", r"\["),
        ("RBRACK", r"\]"),
        ("EQ", r"="),
        ("COMMA", r","),
        ("KW", r"true\b|false\b"),
        ("KEY", r"[A-Za-z_][A-Za-z0-9_\-]*"),
        ("STR", r"\"(?:[^\"\\]|\\.)*\""),
        ("NUM", r"[+-]?\d+(?:\.\d+)?"),
        ("OP", r"==|!=|<=|>=|<|>"),
    ]
    toml_sample = (
        "# header\n" +
        "[pkg.section]\n" +
        "name = \"hello \\\"world\\\"\"\n" +
        "enabled = true\n" +
        "truthy = trueish\n" +
        "count = -42\n" +
        "ratio = 3.14\n" +
        "cmp = a == b <= c\n" +
        "bad = @stop\n"
    )
    for pos, endpos in [(0, None), (9, 55), (0, 2), (len(toml_sample), None), (-3, 200), (20, 10)]:
        _check_scanner_equiv(env, toml_rules, 0, toml_sample, pos, endpos, label = "toml")

    # Scanner with mixed pre-compiled rules (distinct flags), anchors, dot, negated sets, non-ASCII.
    mixed_rules = [
        ("ANCHOR", r"^start"),
        ("CI_PRE", compile("foo", flags = IGNORECASE)),
        ("CS_STR", "bar"),
        ("DOT", r"."),
        ("NL", r"\n"),
    ]
    mixed_specs = [
        ("ANCHOR", r"^start", 0),
        ("CI_PRE", "foo", IGNORECASE),
        ("CS_STR", "bar", 0),
        ("DOT", r".", 0),
        ("NL", r"\n", 0),
    ]
    for txt in ["start FOO bar\n世界", "FOO bar BAR\n", "", "\n"]:
        _check_scanner_equiv(env, mixed_rules, 0, txt, label = "mixed", raw_specs = mixed_specs)

    neg_rules = [
        ("NOT_A", r"[^a]"),
        ("A", r"a+"),
    ]
    for txt in ["baaa世界a", "aaa", ""]:
        _check_scanner_equiv(env, neg_rules, 0, txt, label = "neg")

    # Empty-match rules at start, middle, and EOF.
    empty_rules = [
        ("A", r"a+"),
        ("EOF", r"$"),
    ]
    for pos in [0, 2, 3]:
        _check_scanner_equiv(env, empty_rules, 0, "aab", pos, None, label = "eof")

def equivalence_test(name):
    unit_test(
        name = name,
        impl = _test_equivalence,
    )
