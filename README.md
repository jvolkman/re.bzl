# re.bzl

A pure Starlark implementation of a Regex engine. Vibe coded with Gemini.

## Overview

`re.bzl` provides a Thompson NFA-based regex engine designed for Bazel. It provides a significant subset of RE2 syntax with linear-time performance guarantees.

## Usage

For full API documentation, see [the API Reference](docs/re.md).

```python
load("@re.bzl", "re")

# Search for a pattern
m = re.search(r"(\w+)=(\d+)", "key=123")
if m:
    print(m.group(1)) # "key"
    print(m.group(2)) # "123"

# Replacement
result = re.sub(r"a+", "b", "abaac") # "bbbc"

# Find All
tokens = re.findall(r"\w+", "hello world") # ["hello", "world"]

# Iterate over matches (a list of MatchObjects)
for m in re.finditer(r"(\w+)=(\d+)", "a=1 b=2"):
    print(m.group(1), m.span()) # "a" (0, 3), then "b" (4, 7)

# Full Match
is_exact = re.fullmatch(r"v\d+\.\d+", "v1.2") # <MatchObject> or None

# Pre-compile for reuse (more efficient for multiple searches)
prog = re.compile(r"\d+")
if prog.search("123"):
    print("Found digits")
```

## Performance and Feasibility

This was mostly done as a fun project. Starlark (or any build configuration language) is not an optimal tool for building a regex engine.

That said, it _does_ work, and by optimizing for performance within the constraints of Starlark (offloading as much work as possible to Java-backed string methods), it has shown to be as fast as custom parsing logic in when used on real-world input in [toml.bzl](https://github.com/jvolkman/toml.bzl) while offering concise way to describe token matching expressions.

## Syntax Reference

`re.bzl` aims to support most of RE2 syntax. Below is a detailed reference of supported features.

### Single-character expressions

| Syntax         | Description                                        |
| :------------- | :------------------------------------------------- |
| `.`            | any character, possibly including newline (s=true) |
| `[xyz]`        | character class                                    |
| `[^xyz]`       | negated character class                            |
| `\d`           | Perl character class (digits)                      |
| `\D`           | negated Perl character class                       |
| `[[:alpha:]]`  | ASCII character class                              |
| `[[:^alpha:]]` | negated ASCII character class                      |

### Composites

| Syntax | Description             |
| :----- | :---------------------- |
| `xy`   | `x` followed by `y`     |
| `x\|y` | `x` or `y` (prefer `x`) |

### Repetitions

| Syntax    | Description                                 |
| :-------- | :------------------------------------------ |
| `x*`      | zero or more `x`, prefer more               |
| `x+`      | one or more `x`, prefer more                |
| `x?`      | zero or one `x`, prefer one                 |
| `x{n,m}`  | `n` or `n`+1 or ... or `m` `x`, prefer more |
| `x{n,}`   | `n` or more `x`, prefer more                |
| `x{n}`    | exactly `n` `x`                             |
| `x*?`     | zero or more `x`, prefer fewer              |
| `x+?`     | one or more `x`, prefer fewer               |
| `x??`     | zero or one `x`, prefer zero                |
| `x{n,m}?` | `n` or ... or `m` `x`, prefer fewer         |
| `x{n,}?`  | `n` or more `x`, prefer fewer               |
| `x{n}?`   | exactly `n` `x`                             |

### Grouping

| Syntax         | Description                                   |
| :------------- | :-------------------------------------------- |
| `(re)`         | numbered capturing group (submatch)           |
| `(?P<name>re)` | named & numbered capturing group (submatch)   |
| `(?<name>re)`  | named & numbered capturing group (submatch)   |
| `(?:re)`       | non-capturing group                           |
| `(?flags)`     | set flags within current group; non-capturing |
| `(?flags:re)`  | set flags during re; non-capturing            |

### Flags

| Flag | API Constant(s)         | Description                                                       |
| :--- | :---------------------- | :---------------------------------------------------------------- |
| `i`  | `re.I`, `re.IGNORECASE` | case-insensitive (default false)                                  |
| `m`  | `re.M`, `re.MULTILINE`  | multi-line mode: `^` and `$` match begin/end line (default false) |
| `s`  | `re.S`, `re.DOTALL`     | let `.` match `\n` (default false)                                |
| `x`  | `re.X`, `re.VERBOSE`    | verbose: ignore whitespace and allow comments (default false)     |
| `U`  | `re.U`, `re.UNGREEDY`   | ungreedy: swap meaning of `x*` and `x*?`, etc (default false)     |

### Empty strings (Anchors)

| Syntax | Description                           |
| :----- | :------------------------------------ |
| `^`    | at beginning of text or line (m=true) |
| `$`    | at end of text or line (m=true)       |
| `\A`   | at beginning of text                  |
| `\z`   | at end of text                        |
| `\Z`   | at end of text (Python's spelling)    |
| `\b`   | at ASCII word boundary                |
| `\B`   | not at ASCII word boundary            |

### Escape sequences

| Syntax    | Description                                      |
| :-------- | :----------------------------------------------- |
| `\a`      | bell (≡ `\007`)                                  |
| `\f`      | form feed (≡ `\014`)                             |
| `\t`      | horizontal tab (≡ `\011`)                        |
| `\n`      | newline (≡ `\012`)                               |
| `\r`      | carriage return (≡ `\015`)                       |
| `\v`      | vertical tab character (≡ `\013`)                |
| `\123`    | octal character code (up to three digits)        |
| `\x7F`    | hex character code (exactly two digits)          |
| `\x{7F}`  | hex character code                               |
| `\Q...\E` | literal text `...` even if `...` has punctuation |

### ASCII Character Classes

| Syntax         | Description                                |
| :------------- | :----------------------------------------- |
| `[[:alnum:]]`  | alphanumeric (≡ `[0-9A-Za-z]`)             |
| `[[:alpha:]]`  | alphabetic (≡ `[A-Za-z]`)                  |
| `[[:ascii:]]`  | ASCII (≡ `[\x00-\x7F]`)                    |
| `[[:blank:]]`  | blank (≡ `[\t ]`)                          |
| `[[:cntrl:]]`  | control (≡ `[\x00-\x1F\x7F]`)              |
| `[[:digit:]]`  | digits (≡ `[0-9]`)                         |
| `[[:graph:]]`  | graphical (≡ `[!-~]`)                      |
| `[[:lower:]]`  | lower case (≡ `[a-z]`)                     |
| `[[:print:]]`  | printable (≡ `[ -~]`)                      |
| `[[:punct:]]`  | punctuation (≡ `[!-/:-@[-` + "`" + `{-~]`) |
| `[[:space:]]`  | whitespace (≡ `[\t\n\v\f\r ]`)             |
| `[[:upper:]]`  | upper case (≡ `[A-Z]`)                     |
| `[[:word:]]`   | word characters (≡ `[0-9A-Za-z_]`)         |
| `[[:xdigit:]]` | hex digit (≡ `[0-9A-Fa-f]`)                |

## Compatibility

`re.bzl` aims for high compatibility with [RE2 syntax](https://github.com/google/re2/blob/main/doc/syntax.txt). Most non-Unicode features are supported.

Like RE2, `re.bzl` does not support backreferences and lookarounds.

### Unicode Support

Starlark strings are sequences of **environment-dependent** elements (UTF-K).

- In **Bazel (Java)**: Strings are UTF-16. `.` matches one UTF-16 code unit. Non-BMP characters (like `🚀`) are 2 units (surrogate pair). `len('🚀') == 2`.
- In **starlark-go**: Strings are UTF-8. `.` matches one byte. `🚀` is 4 bytes. `len('🚀') == 4`.
- Character classes `[...]` and `[^...]` operate on these individual elements.
- Quantifiers apply to the preceding atom. For multibyte/multi-unit characters, you must group them (e.g., `(🚀)+`) to match the full sequence.
- Unicode character categories (`\p{...}`) are not supported.

## Installation

Add the following to your `MODULE.bazel`:

```python
bazel_dep(name = "re.bzl", version = "0.1.0")
```

## License

Apache 2.0
