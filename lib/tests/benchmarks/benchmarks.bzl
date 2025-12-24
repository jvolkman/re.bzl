"""Benchmarks for the Starlark regex engine."""

load("//lib:re.bzl", "compile", "match", "search")

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

# buildifier: disable=print
def run_benchmarks(n = 0):
    """Runs all benchmarks.

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
    print("Running fast_path optimizations...")
    _benchmark_fast_path_group(n)
