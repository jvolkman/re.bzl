"""Benchmarks for the Starlark regex engine."""

load("//lib:re.bzl", "compile", "search")

def benchmark_simple_match(n):
    """Simple literal match.

    Args:
      n: Number of iterations.
    """
    p = compile("abc")
    for _ in range(n):
        search(p, "abc")

def benchmark_complex_match(n):
    """Complex regex with groups and alternations.

    Args:
      n: Number of iterations.
    """
    p = compile(r"(\w+)=(\d+)|(\w+):(\w+)")
    for _ in range(n):
        search(p, "key=123")
        search(p, "user:admin")

def benchmark_backtracking(n):
    """Pathological case for backtracking (though NFA should handle it well).

    Args:
      n: Number of iterations.
    """
    p = compile("a?a?a?a?a?a?a?a?a?a?aaaaaaaaaa")
    for _ in range(n):
        search(p, "aaaaaaaaaa")

def benchmark_large_input(n):
    """Matching against a large string.

    Args:
      n: Number of iterations.
    """
    text = "a" * 1000 + "b"
    p = compile("a*b")
    for _ in range(n):
        search(p, text)

def run_benchmarks(n = 0):
    """Runs all benchmarks.

    Args:
      n: Number of iterations.
    """
    benchmark_simple_match(n)
    benchmark_complex_match(n)

    benchmark_backtracking(n)
    benchmark_large_input(n)
