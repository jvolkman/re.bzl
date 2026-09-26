"""Benchmarks for the Starlark regex engine."""

load("//re:re.bzl", "compile", "findall", "finditer", "match", "search", "split", "sub")

def benchmark_simple_match(n):
    p = compile("abc")
    for _ in range(n):
        search(p, "abc")

def benchmark_complex_match(n):
    p = compile(r"(\w+)=(\d+)|(\w+):(\w+)")
    for _ in range(n):
        search(p, "key=123")
        search(p, "user:admin")

def benchmark_backtracking(n):
    p = compile("a?a?a?a?a?a?a?a?a?a?aaaaaaaaaa")
    for _ in range(n):
        search(p, "aaaaaaaaaa")

def benchmark_large_input(n):
    text = "a" * 1000 + "b"
    p = compile("a*b")
    for _ in range(n):
        search(p, text)

def benchmark_case_insensitive(n):
    p = compile("(?i)xyz")
    text = "ABCDEFG" * 10 + "XYZ"
    for _ in range(n):
        search(p, text)

def benchmark_case_insensitive_greedy(n):
    # Optimized: O(N)
    p = compile("(?i)a*b")
    text = "A" * 1000 + "b"
    for _ in range(n):
        search(p, text)

# New fast-path optimization benchmarks
def _benchmark_fast_path_group(n):
    # Start-Anchored
    p1 = compile(r"^\d+abc$")
    t1 = "12345abc"

    # End-Anchored Search
    p2 = compile(r"\d+abc$")
    t2 = "prefix" * 10 + "123abc"

    # Literal Skip Search
    p3 = compile(r"needle\d+")
    t3 = "haystack " * 10 + "needle999"

    for _ in range(n):
        match(p1, t1)
        search(p2, t2)
        search(p3, t3)

# Very large input benchmark (1MB)
def _benchmark_very_large_input(n):
    text = "a" * 1000000 + "b"
    p = compile(r"a*b")
    for _ in range(n):
        search(p, text)
        match(p, text)

_FILLER = "x" * 20000
_NUMBERS_TEXT = "abc 123 " * 250  # 2000 chars, 250 numbers
_WORDS_TEXT = "lorem ipsum dolor sit amet, " * 50  # 1400 chars, 250 words
_CSV_TEXT = ", ".join(["field%d" % i for i in range(1000)])
_TOML_DOC = (
    "# a comment line\n" +
    "[section.sub]\n" +
    "key_1 = \"value \\\" x\"\n" +
    "num = 12345\n" +
    "float = 3.14\n" +
    "flag = true\n" +
    "arr = [1, 2, 3]\n"
) * 60  # ~6KB
_TOKEN_PATTERNS = [
    r"[ \t]+",
    r"\r?\n",
    r"#[^\n]*",
    r"\[",
    r"\]",
    r"[A-Za-z_][A-Za-z0-9_\-]*",
    r"=",
    r"\"(?:[^\"\\]|\\.)*\"",
    r"[+-]?\d+(?:\.\d+)?",
    r"[{},.]",
]

def benchmark_search_early_match(n):
    # A match near the start should not cost O(len(input)).
    p = compile(r"\d+")
    text = "abc123" + _FILLER
    for _ in range(n):
        search(p, text)

def benchmark_search_no_match(n):
    p = compile(r"\d+[a-z]")
    for _ in range(n):
        search(p, _FILLER)

def benchmark_findall_numbers(n):
    p = compile(r"\d+")
    for _ in range(n):
        findall(p, _NUMBERS_TEXT)

def benchmark_findall_words(n):
    p = compile(r"\b\w+\b")
    for _ in range(n):
        findall(p, _WORDS_TEXT)

def benchmark_finditer_numbers(n):
    # Like findall_numbers, plus a MatchObject per match.
    p = compile(r"\d+")
    for _ in range(n):
        finditer(p, _NUMBERS_TEXT)

def benchmark_sub_whitespace(n):
    p = compile(r"\s+")
    for _ in range(n):
        sub(p, " ", _WORDS_TEXT)

def benchmark_split_csv(n):
    p = compile(r",\s*")
    for _ in range(n):
        split(p, _CSV_TEXT)

def _tokenize(patterns, text):
    """A lexer that tries each pattern with match(text, pos) at the current position."""
    pos = 0
    for _ in range(len(text)):
        if pos >= len(text):
            break
        end = pos + 1  # Skip a character that no pattern matches.
        for p in patterns:
            m = p.match(text, pos)
            if m != None and m.end() > pos:
                end = m.end()
                break
        pos = end

def benchmark_tokenize(n):
    patterns = [compile(s) for s in _TOKEN_PATTERNS]
    for _ in range(n):
        _tokenize(patterns, _TOML_DOC)

def benchmark_tokenize_keywords(n):
    # A case-insensitive keyword pattern with word boundaries is tried first.
    patterns = [compile(s) for s in [r"(?i)\b(?:true|false)\b"] + _TOKEN_PATTERNS]
    for _ in range(n):
        _tokenize(patterns, _TOML_DOC)

# buildifier: disable=print
def run_benchmarks(n = 0):
    """Runs all benchmarks.

    Benchmarks over large inputs run fewer iterations (n // 10 and below).

    Args:
      n: Number of iterations.
    """

    print("Running simple_match...")
    benchmark_simple_match(n)
    print("Running complex_match...")
    benchmark_complex_match(n)
    print("Running backtracking...")
    benchmark_backtracking(n)
    print("Running large_input...")
    benchmark_large_input(n)
    print("Running case_insensitive...")
    benchmark_case_insensitive(n)
    print("Running case_insensitive_greedy...")
    benchmark_case_insensitive_greedy(n)
    print("Running very_large_input...")
    _benchmark_very_large_input(n)
    print("Running fast_path optimizations...")
    _benchmark_fast_path_group(n)
    print("Running search_early_match...")
    benchmark_search_early_match(n // 10)
    print("Running search_no_match...")
    benchmark_search_no_match(n // 10)
    print("Running findall_numbers...")
    benchmark_findall_numbers(n // 200)
    print("Running findall_words...")
    benchmark_findall_words(n // 200)
    print("Running finditer_numbers...")
    benchmark_finditer_numbers(n // 200)
    print("Running sub_whitespace...")
    benchmark_sub_whitespace(n // 200)
    print("Running split_csv...")
    benchmark_split_csv(n // 200)
    print("Running tokenize...")
    benchmark_tokenize(n // 1000)
    print("Running tokenize_keywords...")
    benchmark_tokenize_keywords(n // 1000)
