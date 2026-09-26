"""Core implementation of Starlark Regex Engine."""

load(
    "//re/private:compiler.bzl",
    "compile_regex",
    "compute_first_skip",
    "optimize_matcher",
)
load(
    "//re/private:vm.bzl",
    "MatchObject",
    "expand_template",
    "fullmatch_bytecode",
    "match_bytecode",
    "parse_replacement_template",
    "search_bytecode",
    "search_regs",
)

# Types
_STRING_TYPE = type("")

def compile(pattern, flags = 0):
    """Compiles a regex pattern into a reusable object.

    The returned object has 'search', 'match', and 'fullmatch' methods that work
    like the top-level functions but with the pattern pre-compiled.

    Args:
      pattern: The regex pattern string.
      flags: Regex flags (e.g. re.I, re.M, re.VERBOSE).

    Returns:
      A struct containing the compiled bytecode and methods:
      - search(text): Scans text for a match. Returns a MatchObject or None.
      - match(text): Checks for a match at the beginning of text. Returns a MatchObject or None.
      - fullmatch(text): Checks for a match of the entire text. Returns a MatchObject or None.
      - pattern: The pattern string.
      - group_count: The number of capturing groups.

      The MatchObject returned by these methods has the following members:
      - group(n=0): Returns the string matched by group n (int or string name).
      - groups(default=None): Returns a tuple of all captured groups.
      - groupdict(default=None): Returns a dictionary containing all the named subgroups.
      - span(n=0): Returns the (start, end) tuple of the match for group n.
      - start(n=0): Returns the start index of the match for group n.
      - end(n=0): Returns the end index of the match for group n.
      - string: The string passed to match/search.
      - re: The compiled regex object.
      - pos: The start position of the search.
      - endpos: The end position of the search.
      - lastindex: The integer index of the last matched capturing group.
      - lastgroup: The name of the last matched capturing group.
    """
    if hasattr(pattern, "bytecode"):
        return pattern

    bytecode, named_groups, group_count, has_case_insensitive = compile_regex(pattern, flags = flags)
    opt = optimize_matcher(bytecode)
    first_skip = compute_first_skip(bytecode)

    def _search(text, pos = 0, endpos = None):
        return search_bytecode(bytecode, text, named_groups, group_count, start_index = pos, end_index = endpos, has_case_insensitive = has_case_insensitive, opt = opt, first_skip = first_skip)

    def _match(text, pos = 0, endpos = None):
        return match_bytecode(bytecode, text, named_groups, group_count, start_index = pos, end_index = endpos, has_case_insensitive = has_case_insensitive, opt = opt, first_skip = first_skip)

    def _fullmatch(text, pos = 0, endpos = None):
        return fullmatch_bytecode(bytecode, text, named_groups, group_count, start_index = pos, end_index = endpos, has_case_insensitive = has_case_insensitive, opt = opt, first_skip = first_skip)

    return struct(
        search = _search,
        match = _match,
        fullmatch = _fullmatch,
        bytecode = bytecode,
        named_groups = named_groups,
        group_count = group_count,
        pattern = pattern,
        has_case_insensitive = has_case_insensitive,
        opt = opt,
        first_skip = first_skip,
    )

def search(pattern, text, flags = 0, pos = 0, endpos = None):
    """Scan through string looking for the first location where the regex pattern produces a match.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.
      flags: Regex flags (only if pattern is a string).
      pos: Start position.
      endpos: End position.

    Returns:
      A MatchObject containing the match results, or None if no match was found.
      See `compile` for details on MatchObject.
    """
    compiled = compile(pattern, flags = flags)
    return search_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = pos, end_index = endpos, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt, first_skip = compiled.first_skip)

def match(pattern, text, flags = 0, pos = 0, endpos = None):
    """Try to apply the pattern at the start of the string.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.
      flags: Regex flags (only if pattern is a string).
      pos: Start position.
      endpos: End position.

    Returns:
      A MatchObject containing the match results, or None if no match was found.
      See `compile` for details on MatchObject.
    """
    compiled = compile(pattern, flags = flags)
    return match_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = pos, end_index = endpos, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt, first_skip = compiled.first_skip)

def fullmatch(pattern, text, flags = 0, pos = 0, endpos = None):
    """Try to apply the pattern to the entire string.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.
      flags: Regex flags (only if pattern is a string).
      pos: Start position.
      endpos: End position.

    Returns:
      A MatchObject containing the match results, or None if no match was found.
      See `compile` for details on MatchObject.
    """
    compiled = compile(pattern, flags = flags)
    return fullmatch_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = pos, end_index = endpos, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt, first_skip = compiled.first_skip)

# buildifier: disable=list-append
def _find_all_regs(compiled, text, limit = 0):
    """Finds the non-overlapping matches of a compiled pattern in text.

    This is the search loop shared by findall, sub and split. As in Python 3.7+,
    a match may start where the previous match ended, but after an empty match,
    another empty match at the same position is skipped.

    Args:
      compiled: The compiled regex object.
      text: The text to search.
      limit: The maximum number of matches to find. If non-positive, all matches
        are found.

    Returns:
      A list with the registers of each match (see search_regs), in order.
    """
    bytecode = compiled.bytecode
    group_count = compiled.group_count
    has_case_insensitive = compiled.has_case_insensitive
    opt = compiled.opt
    first_skip = compiled.first_skip

    input_lower = None
    if has_case_insensitive:
        input_lower = text.lower()

    all_regs = []
    start_index = 0
    must_advance = False

    # At most len(text) + 1 empty and len(text) non-empty matches, plus the final
    # failed search.
    for _ in range(2 * len(text) + 2):
        if limit > 0 and len(all_regs) >= limit:
            break

        # Use search_regs to avoid creating a MatchObject per match.
        regs = search_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive, opt = opt, input_lower = input_lower, first_skip = first_skip, must_advance = must_advance)

        # regs[0] == -1 should not happen if search_regs returns non-None.
        if not regs or regs[0] == -1:
            break
        all_regs += [regs]

        # The next match may start where this one ended, but must not be empty
        # there if this one was empty.
        must_advance = regs[1] == regs[0]
        start_index = regs[1]

    return all_regs

def findall(pattern, text, flags = 0):
    """Return all non-overlapping matches of pattern in string, as a list of strings or tuples.

    As in Python, the result depends on the number of capturing groups in the
    pattern. With no groups, each item is the string matched by the whole pattern.
    With one group, it is the string matched by that group. With more groups, it is
    a tuple of the strings matched by the groups. A group that did not take part in
    a match is reported as "".

    Empty matches are included in the result. As in Python 3.7+, a non-empty match
    may start where the previous empty match ended.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.
      flags: Regex flags (only if pattern is a string).

    Returns:
      A list of matching strings or tuples of matching groups.
    """
    compiled = compile(pattern, flags = flags)
    group_count = compiled.group_count
    all_regs = _find_all_regs(compiled, text)

    # Extract results (shaped like Python's: see the docstring)
    if group_count == 0:
        return [text[regs[0]:regs[1]] for regs in all_regs]
    if group_count == 1:
        return [text[regs[2]:regs[3]] if regs[2] != -1 else "" for regs in all_regs]
    group_starts = range(2, 2 * group_count + 2, 2)
    return [
        tuple([text[regs[i]:regs[i + 1]] if regs[i] != -1 else "" for i in group_starts])
        for regs in all_regs
    ]

# buildifier: disable=list-append
def sub(pattern, repl, text, count = 0, flags = 0):
    """Return the string obtained by replacing the leftmost non-overlapping occurrences of the pattern in text by the replacement repl.

    Empty matches are replaced too. As in Python 3.7+, a non-empty match may start
    where the previous empty match ended.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      repl: The replacement string or function.
      text: The text to search.
      count: The maximum number of pattern occurrences to replace.
        If non-positive, all occurrences are replaced.
      flags: Regex flags (only if pattern is a string).

    Returns:
      The text with the replacements applied.
    """

    # We need named groups for \g<name>, so we need the compiled object.
    compiled = compile(pattern, flags = flags)
    group_count = compiled.group_count
    text_len = len(text)

    # Pre-parse replacement string if it's a string; otherwise it is a function.
    repl_template = None
    if type(repl) == _STRING_TYPE:
        repl_template = parse_replacement_template(repl, compiled.named_groups)

    res_parts = []
    last_idx = 0
    for regs in _find_all_regs(compiled, text, count):
        match_start = regs[0]
        match_end = regs[1]

        # Append text before match
        res_parts += [text[last_idx:match_start]]

        # Calculate replacement
        if repl_template == None:
            # Slow path: Create proper match object using vm.MatchObject.
            # Like Python, pos/endpos describe the whole sub() call.
            m = MatchObject(text, regs, compiled, 0, text_len)
            replacement = repl(m)
        else:
            # Construct groups tuple only if needed
            groups = []
            for i in range(1, group_count + 1):
                s = regs[i * 2]
                e = regs[i * 2 + 1]
                if s == -1:
                    groups += [None]
                else:
                    groups += [text[s:e]]
            replacement = expand_template(repl_template, text[match_start:match_end], tuple(groups))

        res_parts += [replacement]
        last_idx = match_end

    res_parts += [text[last_idx:]]
    return "".join(res_parts)

# buildifier: disable=list-append
def split(pattern, text, maxsplit = 0, flags = 0):
    """Split the source string by the occurrences of the pattern, returning a list containing the resulting substrings.

    Empty matches split the string too. As in Python 3.7+, a non-empty match may
    start where the previous empty match ended.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to split.
      maxsplit: The maximum number of splits to perform.
        If non-positive, there is no limit on the number of splits.
      flags: Regex flags (only if pattern is a string).

    Returns:
      A list of strings.
    """

    compiled = compile(pattern, flags = flags)
    group_count = compiled.group_count
    res_parts = []
    last_idx = 0
    for regs in _find_all_regs(compiled, text, maxsplit):
        # Append text before match
        res_parts += [text[last_idx:regs[0]]]

        # If capturing groups, append them too (Python behavior)
        if group_count > 0:
            for i in range(1, group_count + 1):
                s = regs[i * 2]
                e = regs[i * 2 + 1]
                if s == -1:
                    res_parts += [None]
                else:
                    res_parts += [text[s:e]]

        last_idx = regs[1]

    res_parts += [text[last_idx:]]
    return res_parts
