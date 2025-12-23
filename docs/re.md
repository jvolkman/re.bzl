<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API for the Starlark regex engine.

<a id="compile"></a>

## compile

<pre>
load("@bazel-regex//lib:re.bzl", "compile")

compile(<a href="#compile-pattern">pattern</a>)
</pre>

Compiles a regex pattern into a reusable object.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="compile-pattern"></a>pattern |  The regex pattern string.   |  none |

**RETURNS**

A struct containing the compiled bytecode and methods.


<a id="findall"></a>

## findall

<pre>
load("@bazel-regex//lib:re.bzl", "findall")

findall(<a href="#findall-pattern">pattern</a>, <a href="#findall-text">text</a>)
</pre>

Return all non-overlapping matches of pattern in string, as a list of strings.

If one or more groups are present in the pattern, return a list of groups.
Empty matches are included in the result.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="findall-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="findall-text"></a>text |  The text to match against.   |  none |

**RETURNS**

A list of matching strings or tuples of matching groups.


<a id="fullmatch"></a>

## fullmatch

<pre>
load("@bazel-regex//lib:re.bzl", "fullmatch")

fullmatch(<a href="#fullmatch-pattern">pattern</a>, <a href="#fullmatch-text">text</a>)
</pre>

Try to apply the pattern to the entire string.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="fullmatch-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="fullmatch-text"></a>text |  The text to match against.   |  none |

**RETURNS**

A dictionary containing the match results (group ID/name -> matched string),
or None if no match was found.


<a id="match"></a>

## match

<pre>
load("@bazel-regex//lib:re.bzl", "match")

match(<a href="#match-pattern">pattern</a>, <a href="#match-text">text</a>)
</pre>

Try to apply the pattern at the start of the string.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="match-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="match-text"></a>text |  The text to match against.   |  none |

**RETURNS**

A dictionary containing the match results (group ID/name -> matched string),
or None if no match was found.


<a id="search"></a>

## search

<pre>
load("@bazel-regex//lib:re.bzl", "search")

search(<a href="#search-pattern">pattern</a>, <a href="#search-text">text</a>)
</pre>

Scan through string looking for the first location where the regex pattern produces a match.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="search-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="search-text"></a>text |  The text to match against.   |  none |

**RETURNS**

A dictionary containing the match results (group ID/name -> matched string),
or None if no match was found.


<a id="split"></a>

## split

<pre>
load("@bazel-regex//lib:re.bzl", "split")

split(<a href="#split-pattern">pattern</a>, <a href="#split-text">text</a>, <a href="#split-maxsplit">maxsplit</a>)
</pre>

Split the source string by the occurrences of the pattern, returning a list containing the resulting substrings.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="split-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="split-text"></a>text |  The text to split.   |  none |
| <a id="split-maxsplit"></a>maxsplit |  The maximum number of splits to perform. If non-positive, there is no limit on the number of splits.   |  `0` |

**RETURNS**

A list of strings.


<a id="sub"></a>

## sub

<pre>
load("@bazel-regex//lib:re.bzl", "sub")

sub(<a href="#sub-pattern">pattern</a>, <a href="#sub-repl">repl</a>, <a href="#sub-text">text</a>, <a href="#sub-count">count</a>)
</pre>

Return the string obtained by replacing the leftmost non-overlapping occurrences of the pattern in text by the replacement repl.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="sub-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="sub-repl"></a>repl |  The replacement string or function.   |  none |
| <a id="sub-text"></a>text |  The text to search.   |  none |
| <a id="sub-count"></a>count |  The maximum number of pattern occurrences to replace. If non-positive, all occurrences are replaced.   |  `0` |

**RETURNS**

The text with the replacements applied.


