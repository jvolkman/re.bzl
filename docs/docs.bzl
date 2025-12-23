"""Macros for generating Starlark documentation."""

load("@bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@stardoc//stardoc:stardoc.bzl", "stardoc")

def stardoc_with_diff_test(name, bzl_library_target, out_file = None, input_file = None, symbol_names = [], **kwargs):
    """Generates documentation for a Starlark library and verifies it with a test.

    Args:
      name: The name of the target.
      bzl_library_target: The bzl_library target to generate docs for.
      out_file: The name of the output markdown file. Defaults to <name>.md.
      input_file: The .bzl file to generate docs for. If not provided, assumed to be <name>.bzl (relative to package).
      symbol_names: List of symbols to export.
      **kwargs: Additional arguments passed to stardoc.
    """
    if not out_file:
        out_file = name + ".md"

    # Generate the Starlark documentation
    doc_target_name = name + "_doc_gen"
    stardoc(
        name = doc_target_name,
        out = out_file.replace(".md", ".gen.md"),  # Generate to a temporary location
        input = input_file,
        deps = [bzl_library_target],
        symbol_names = symbol_names,
        **kwargs
    )

    # Verify that the generated docs match the source file
    write_source_files(
        name = name,
        files = {out_file: ":" + doc_target_name},
        diff_test = True,
    )
