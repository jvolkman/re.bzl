# regexlib

A lightweight, pure Starlark implementation of a Regex Engine.

## Overview

`regexlib` provides a Thompson NFA-based regex engine designed for Starlark environments (like Bazel) where the standard `re` module is unavailable. It supports a significant subset of RE2 syntax and is optimized for correctness and ease of integration.

## Features

- **Core Syntax**: Literals, `.`, `*`, `+`, `?`, `|`, `()`, `[]`, `^`, `$`.
- **Character Classes**: Predefined classes (`\d`, `\w`, `\s`) and POSIX classes (`[[:digit:]]`, etc.).
- **Groups**: Capturing and non-capturing groups, named groups (`(?P<name>...)`, `(?<name>...)`).
- **Quantifiers**: Greedy and lazy quantifiers, repetition ranges (`{n,m}`).
- **Anchors**: Absolute anchors (`\A`, `\z`), word boundaries (`\b`, `\B`).
- **Flags**: Case-insensitivity (`(?i)`), multiline (`(?m)`), dot-all (`(?s)`), and ungreedy (`(?U)`).
- **Quoted Literals**: `\Q...\E` support.

## Compatibility

`regexlib` aims for high compatibility with [RE2 syntax](https://github.com/google/re2/blob/main/doc/syntax.txt). Most non-Unicode features are supported.

### Key Differences
- **Unicode**: Currently, only ASCII/UTF-8 byte-level matching is supported. Unicode character classes (`\p{...}`) are not implemented.
- **Backreferences**: Not supported (consistent with RE2's linear-time guarantee).
- **Lookarounds**: Not supported.

## Installation

Add the following to your `MODULE.bazel`:

```python
bazel_dep(name = "regexlib", version = "0.1.0")
```

## Usage

```python
load("@regexlib//lib:re.bzl", "search", "match", "findall", "sub", "split")

# Search for a pattern
m = search(r"(\w+)=(\d+)", "key=123")
if m:
    print(m.group(1)) # "key"
    print(m.group(2)) # "123"

# Replace matches
result = sub(r"a+", "b", "abaac") # "bbbc"
```

## Development

### Running Tests

```bash
bazel test //lib/tests:all_tests
```

## License

Apache 2.0
