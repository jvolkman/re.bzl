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

def benchmark_fast_path(n):
    p = compile(r"^1\w*")
    text = "1" + "a" * 100
    for _ in range(n):
        match(p, text)

# buildifier: disable=print
def run_benchmarks(n = 0):
    """Runs all benchmarks.

    Args:
      n: Number of iterations.
    """

    benchmark_simple_match(n)
    print("Running complex_match...")
    benchmark_complex_match(n)
    print("Running backtracking...")
    benchmark_backtracking(n)
    print("Running large_input...")
    benchmark_large_input(n)
    print("Running case_insensitive...")
    benchmark_case_insensitive(n)
    print("Running fast_path...")
    benchmark_fast_path(n)
