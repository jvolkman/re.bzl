# Development Notes

## Profiling Starlark Performance

The `restar` library executes its regex logic (compilation and matching) during the **analysis phase** of the Bazel build, not the execution phase. This means standard test execution times (e.g., `PASSED in 0.3s`) reported by `bazel test` do not reflect the actual runtime of the regex engine.

To accurately measure performance changes:

1.  **Clean the cache**: Force a full re-analysis.
    ```bash
    bazel clean
    ```
2.  **Profile the build**: Use the `--starlark_cpu_profile` flag to capture Starlark analysis time, and `--nobuild` to skip execution.
    ```bash
    bazel build //lib/tests:repro_benchmark --starlark_cpu_profile=profile.gz --nobuild
    ```
3.  **Analyze**: Use a tool like `pprof` or Chrome Tracing (`chrome://tracing`) to inspect the `profile.gz` file and look for Starlark execution phases.

## Workflow Best Practices

- **Atomic Commits**: Changes should be committed after reaching a good stopping point (e.g., a single logic fix or a distinct optimization) before moving onto the next change. This makes it easier to track regressions and review code.

## Starlark Performance Best Practices

Based on profiling within the `restar` codebase, the following patterns are significantly more efficient in Starlark:

### 1. Prefer Operators Over Method Calls
Operators are built-in to the Starlark interpreter and avoid the overhead of method lookup and dispatch.

- **List Append**: Use `list += [item]` instead of `list.append(item)`.
    - *Result*: `+= [item]` is approximately **2x faster** than `.append()`.
- **List Copy**: Use `list_copy = original[:]` instead of `list_copy = list(original)`.
    - *Result*: `[:]` slicing is approximately **2.5x faster** than `list()`.

### 2. Fast Path Scanning
For unanchored searches, use `input_str.find(literal)` or `input_str.lstrip(chars)` to quickly skip large portions of the input before starting the full NFA simulation.

### 3. Caching Greedy Loops
When using `OP_GREEDY_LOOP` in unanchored searches, memoize the absolute end position of the loop. This prevents $O(N^2)$ behavior where the same segment is re-scanned for every possible start position.
