<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API for the Starlark regex engine.

<a id="re.compile"></a>

## re.compile

<pre>
load("@re.bzl", "re")

re.compile(<a href="#re.compile-pattern">pattern</a>, <a href="#re.compile-flags">flags</a>)
</pre>

Compiles a regex pattern into a reusable object.

The returned object has 'search', 'match', and 'fullmatch' methods that work
like the top-level functions but with the pattern pre-compiled.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="re.compile-pattern"></a>pattern |  The regex pattern string.   |  none |
| <a id="re.compile-flags"></a>flags |  Regex flags (e.g. re.I, re.M, re.VERBOSE).   |  `0` |

**RETURNS**

A struct containing the compiled bytecode and methods:
- search(text): Scans text for a match. Returns a MatchObject or None.
- match(text): Checks for a match at the beginning of text. Returns a MatchObject or None.
- fullmatch(text): Checks for a match of the entire text. Returns a MatchObject or None.
- pattern: The pattern string.
- group_count: The number of capturing groups.

The MatchObject returned by these methods has the following members:
- group(n=0): Returns the string matched by group n (int or string name).
- groups(default=None): Returns a tuple of all captured groups.
- span(n=0): Returns the (start, end) tuple of the match for group n.
- start(n=0): Returns the start index of the match for group n.
- end(n=0): Returns the end index of the match for group n.
- string: The string passed to match/search.
- re: The compiled regex object.
- pos: The start position of the search.
- endpos: The end position of the search.
- lastindex: The integer index of the last matched capturing group.
- lastgroup: The name of the last matched capturing group.


<a id="re.findall"></a>

## re.findall

<pre>
load("@re.bzl", "re")

re.findall(<a href="#re.findall-pattern">pattern</a>, <a href="#re.findall-text">text</a>, <a href="#re.findall-flags">flags</a>)
</pre>

Return all non-overlapping matches of pattern in string, as a list of strings.

If one or more groups are present in the pattern, return a list of groups.
Empty matches are included in the result.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="re.findall-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="re.findall-text"></a>text |  The text to match against.   |  none |
| <a id="re.findall-flags"></a>flags |  Regex flags (only if pattern is a string).   |  `0` |

**RETURNS**

A list of matching strings or tuples of matching groups.


<a id="re.fullmatch"></a>

## re.fullmatch

<pre>
load("@re.bzl", "re")

re.fullmatch(<a href="#re.fullmatch-pattern">pattern</a>, <a href="#re.fullmatch-text">text</a>, <a href="#re.fullmatch-flags">flags</a>, <a href="#re.fullmatch-pos">pos</a>, <a href="#re.fullmatch-endpos">endpos</a>)
</pre>

Try to apply the pattern to the entire string.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="re.fullmatch-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="re.fullmatch-text"></a>text |  The text to match against.   |  none |
| <a id="re.fullmatch-flags"></a>flags |  Regex flags (only if pattern is a string).   |  `0` |
| <a id="re.fullmatch-pos"></a>pos |  Start position.   |  `0` |
| <a id="re.fullmatch-endpos"></a>endpos |  End position.   |  `None` |

**RETURNS**

A MatchObject containing the match results, or None if no match was found.
See `compile` for details on MatchObject.


<a id="re.match"></a>

## re.match

<pre>
load("@re.bzl", "re")

re.match(<a href="#re.match-pattern">pattern</a>, <a href="#re.match-text">text</a>, <a href="#re.match-flags">flags</a>, <a href="#re.match-pos">pos</a>, <a href="#re.match-endpos">endpos</a>)
</pre>

Try to apply the pattern at the start of the string.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="re.match-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="re.match-text"></a>text |  The text to match against.   |  none |
| <a id="re.match-flags"></a>flags |  Regex flags (only if pattern is a string).   |  `0` |
| <a id="re.match-pos"></a>pos |  Start position.   |  `0` |
| <a id="re.match-endpos"></a>endpos |  End position.   |  `None` |

**RETURNS**

A MatchObject containing the match results, or None if no match was found.
See `compile` for details on MatchObject.


<a id="re.search"></a>

## re.search

<pre>
load("@re.bzl", "re")

re.search(<a href="#re.search-pattern">pattern</a>, <a href="#re.search-text">text</a>, <a href="#re.search-flags">flags</a>, <a href="#re.search-pos">pos</a>, <a href="#re.search-endpos">endpos</a>)
</pre>

Scan through string looking for the first location where the regex pattern produces a match.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="re.search-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="re.search-text"></a>text |  The text to match against.   |  none |
| <a id="re.search-flags"></a>flags |  Regex flags (only if pattern is a string).   |  `0` |
| <a id="re.search-pos"></a>pos |  Start position.   |  `0` |
| <a id="re.search-endpos"></a>endpos |  End position.   |  `None` |

**RETURNS**

A MatchObject containing the match results, or None if no match was found.
See `compile` for details on MatchObject.


<a id="re.split"></a>

## re.split

<pre>
load("@re.bzl", "re")

re.split(<a href="#re.split-pattern">pattern</a>, <a href="#re.split-text">text</a>, <a href="#re.split-maxsplit">maxsplit</a>, <a href="#re.split-flags">flags</a>)
</pre>

Split the source string by the occurrences of the pattern, returning a list containing the resulting substrings.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="re.split-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="re.split-text"></a>text |  The text to split.   |  none |
| <a id="re.split-maxsplit"></a>maxsplit |  The maximum number of splits to perform. If non-positive, there is no limit on the number of splits.   |  `0` |
| <a id="re.split-flags"></a>flags |  Regex flags (only if pattern is a string).   |  `0` |

**RETURNS**

A list of strings.


<a id="re.sub"></a>

## re.sub

<pre>
load("@re.bzl", "re")

re.sub(<a href="#re.sub-pattern">pattern</a>, <a href="#re.sub-repl">repl</a>, <a href="#re.sub-text">text</a>, <a href="#re.sub-count">count</a>, <a href="#re.sub-flags">flags</a>)
</pre>

Return the string obtained by replacing the leftmost non-overlapping occurrences of the pattern in text by the replacement repl.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="re.sub-pattern"></a>pattern |  The regex pattern string or a compiled regex object.   |  none |
| <a id="re.sub-repl"></a>repl |  The replacement string or function.   |  none |
| <a id="re.sub-text"></a>text |  The text to search.   |  none |
| <a id="re.sub-count"></a>count |  The maximum number of pattern occurrences to replace. If non-positive, all occurrences are replaced.   |  `0` |
| <a id="re.sub-flags"></a>flags |  Regex flags (only if pattern is a string).   |  `0` |

**RETURNS**

The text with the replacements applied.


