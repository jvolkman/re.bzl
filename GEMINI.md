# Development Notes

## Profiling Starlark Performance

The `re.bzl` library executes its regex logic (compilation and matching) during the **analysis phase** of the Bazel build, not the execution phase. This means standard test execution times (e.g., `PASSED in 0.3s`) reported by `bazel test` do not reflect the actual runtime of the regex engine.

To accurately measure performance changes:

1.  **Clean the cache**: Force a full re-analysis. (Alternatively, add a throwaway `--define=run=$(date +%s%N)` to the command below: changing the configuration re-analyzes without discarding the cache.)
    ```bash
    bazel clean
    ```
2.  **Profile the build**: Use the `--starlark_cpu_profile` flag to capture Starlark analysis time, and `--nobuild` to skip execution.
    ```bash
    bazel build //re/tests/benchmarks:benchmark_test --starlark_cpu_profile=profile.gz --nobuild
    ```
3.  **Analyze**: Use a tool like `pprof` or Chrome Tracing (`chrome://tracing`) to inspect the `profile.gz` file and look for Starlark execution phases. `pprof -top -cum profile.gz` lists the cumulative time of each function, including each `benchmark_*` function in `re/tests/benchmarks/benchmarks.bzl`.

## Workflow Best Practices

- **Atomic Commits**: Changes should be committed after reaching a good stopping point (e.g., a single logic fix or a distinct optimization) before moving onto the next change. This makes it easier to track regressions and review code.

## Starlark Performance Best Practices

Based on profiling within the `re.bzl` codebase, the following patterns are significantly more efficient in Starlark:

### 1. Prefer Operators Over Method Calls

Operators are built-in to the Starlark interpreter and avoid the overhead of method lookup and dispatch.

- **List Append**: Use `list += [item]` instead of `list.append(item)`.
  - _Result_: `+= [item]` is approximately **2x faster** than `.append()`.
- **List Copy**: Use `list_copy = original[:]` instead of `list_copy = list(original)`.
  - _Result_: `[:]` slicing is approximately **2.5x faster** than `list()`.

### 2. Fast Path Scanning

For unanchored searches, use `input_str.find(literal)` or `input_str.lstrip(chars)` to quickly skip large portions of the input before starting the full NFA simulation.

### 3. Caching Greedy Loops

When using `OP_GREEDY_LOOP` in unanchored searches, memoize the absolute end position of the loop. This prevents $O(N^2)$ behavior where the same segment is re-scanned for every possible start position.

### 4. Keep Hot Paths Flat

A `def` call is expensive compared to operators, and built-in calls such as `len()` are not free either. A lexer calls `match()` at every position, so per-call overhead adds up.

- _Result_: One extra helper call per `match()` slowed a lexer benchmark by about **10%**; inlining the same checks was within noise (see the pos/endpos clamping in `search_bytecode`).
- _Result_: Rejecting an impossible first character in the compiled object's `match()`, two calls earlier than before, made the lexer benchmarks **9–14%** faster.

### 5. Sort `lstrip`/`rstrip` Character Sets

`lstrip(chars)` and `rstrip(chars)` build a matcher from `chars` on every call, and sort it. Pass the characters already sorted (e.g. `"".join(sorted(chars))`), especially for a set that is used repeatedly.

- _Result_: A 64-character set costs about **0.40 µs** per call sorted, against **0.86 µs** unsorted.

### 6. Slices Copy

`s[a:b]` copies the characters; only the whole string (`s[:len(s)]`) is free. Scan large inputs in bounded windows that start small and grow (see `_windowed_lstrip`), and pass bounds to helpers instead of slicing the input to them.

- _Result_: Starting the windows at 64 characters instead of 64 KB made `findall()` over 200 KB about **20% faster**: every match used to copy a 64 KB window.

### 7. Verify With A/B Timings

The Starlark CPU profiler's attribution to built-in calls is unreliable: it charged a large share of `_get_epsilon_closure` to `stack.pop()` and `len()`, yet `len()` costs the same for any string length, and replacing `pop()` with an index-based stack made no measurable difference. Confirm an optimization by timing both versions with the same iteration count, not from profile percentages or a single noisy baseline.
