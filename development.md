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
