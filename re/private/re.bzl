"""Core implementation of Starlark Regex Engine."""

load(
    "//re/private:compiler.bzl",
    "compile_regex",
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
_FUNCTION_TYPE = type(len)

def compile(pattern):
    """Compiles a regex pattern into a reusable object.

    The returned object has 'search', 'match', and 'fullmatch' methods that work
    like the top-level functions but with the pattern pre-compiled.

    Args:
      pattern: The regex pattern string.

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

    bytecode, named_groups, group_count, has_case_insensitive = compile_regex(pattern)
    opt = optimize_matcher(bytecode)

    def _search(text):
        return search_bytecode(bytecode, text, named_groups, group_count, has_case_insensitive = has_case_insensitive, opt = opt)

    def _match(text):
        return match_bytecode(bytecode, text, named_groups, group_count, has_case_insensitive = has_case_insensitive, opt = opt)

    def _fullmatch(text):
        return fullmatch_bytecode(bytecode, text, named_groups, group_count, has_case_insensitive = has_case_insensitive, opt = opt)

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
    )

def search(pattern, text):
    """Scan through string looking for the first location where the regex pattern produces a match.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.

    Returns:
      A MatchObject containing the match results, or None if no match was found.
      See `compile` for details on MatchObject.
    """
    compiled = compile(pattern)
    return search_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = 0, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt)

def match(pattern, text):
    """Try to apply the pattern at the start of the string.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.

    Returns:
      A MatchObject containing the match results, or None if no match was found.
      See `compile` for details on MatchObject.
    """
    compiled = compile(pattern)
    return match_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = 0, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt)

def fullmatch(pattern, text):
    """Try to apply the pattern to the entire string.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.

    Returns:
      A MatchObject containing the match results, or None if no match was found.
      See `compile` for details on MatchObject.
    """
    compiled = compile(pattern)
    return fullmatch_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = 0, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt)

# buildifier: disable=list-append
def findall(pattern, text):
    """Return all non-overlapping matches of pattern in string, as a list of strings.

    If one or more groups are present in the pattern, return a list of groups.
    Empty matches are included in the result.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.

    Returns:
      A list of matching strings or tuples of matching groups.
    """
    compiled = compile(pattern)
    group_count = compiled.group_count
    matches = []
    start_index = 0
    text_len = len(text)

    # Cache access to frequently used values
    bytecode = compiled.bytecode
    has_case_insensitive = compiled.has_case_insensitive
    opt = compiled.opt

    # Simulate while loop
    # Max possible matches is len(text) + 1 (for empty matches)
    for _ in range(text_len + 2):
        regs = search_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive, opt = opt)
        if not regs:
            break

        match_start = regs[0]
        match_end = regs[1]

        if match_start == -1:
            # Should not happen if execute returns non-None
            break

        # Extract result
        if group_count == 0:
            matches += [text[match_start:match_end]]
        else:
            # Return groups
            groups = []
            for i in range(1, group_count + 1):
                s = regs[i * 2]
                e = regs[i * 2 + 1]
                if s == -1:
                    groups += [None]
                else:
                    groups += [text[s:e]]
            matches += [tuple(groups)]

        # Advance start_index
        if match_end > match_start:
            start_index = match_end
        else:
            # Empty match, advance by 1 to avoid infinite loop
            start_index = match_end + 1

        if start_index > text_len:
            break

    return matches

# buildifier: disable=list-append
def sub(pattern, repl, text, count = 0):
    """Return the string obtained by replacing the leftmost non-overlapping occurrences of the pattern in text by the replacement repl.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      repl: The replacement string or function.
      text: The text to search.
      count: The maximum number of pattern occurrences to replace.
        If non-positive, all occurrences are replaced.

    Returns:
      The text with the replacements applied.
    """

    # We need named groups for \g<name>, so we need the compiled object.
    compiled = compile(pattern)

    res_parts = []
    last_idx = 0
    start_index = 0
    text_len = len(text)
    matches_found = 0

    # Cache values
    bytecode = compiled.bytecode
    group_count = compiled.group_count
    has_case_insensitive = compiled.has_case_insensitive
    opt = compiled.opt
    named_groups = compiled.named_groups

    # Pre-parse replacement string if it's a string
    repl_template = None
    if type(repl) != _FUNCTION_TYPE:
        repl_template = parse_replacement_template(repl, named_groups)

    # Simulate while loop
    for _ in range(text_len + 2):
        if count > 0 and matches_found >= count:
            break

        # Use search_regs to avoid creating MatchObject
        regs = search_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive, opt = opt)
        if not regs:
            break

        match_start = regs[0]
        match_end = regs[1]

        # Append text before match
        res_parts += [text[last_idx:match_start]]

        # Calculate replacement
        match_str = text[match_start:match_end]

        # Construct groups tuple only if needed

        groups = []
        for i in range(1, group_count + 1):
            s = regs[i * 2]
            e = regs[i * 2 + 1]
            if s == -1:
                groups += [None]
            else:
                groups += [text[s:e]]
        groups = tuple(groups)

        if type(repl) == _FUNCTION_TYPE:
            # Slow path: Create proper match object using vm.MatchObject
            # Use the loaded MatchObject
            m = MatchObject(text, regs, compiled, start_index, text_len)
            replacement = repl(m)
        else:
            replacement = expand_template(repl_template, match_str, groups)

        res_parts += [replacement]

        last_idx = match_end
        matches_found += 1

        # Advance start_index
        if match_end > match_start:
            start_index = match_end
        else:
            start_index = match_end + 1

        if start_index > text_len:
            break

    res_parts += [text[last_idx:]]
    return "".join(res_parts)

# buildifier: disable=list-append
def split(pattern, text, maxsplit = 0):
    """Split the source string by the occurrences of the pattern, returning a list containing the resulting substrings.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to split.
      maxsplit: The maximum number of splits to perform.
        If non-positive, there is no limit on the number of splits.

    Returns:
      A list of strings.
    """

    compiled = compile(pattern)
    res_parts = []
    last_idx = 0
    start_index = 0
    text_len = len(text)
    splits_found = 0

    # Cache values
    bytecode = compiled.bytecode
    group_count = compiled.group_count
    has_case_insensitive = compiled.has_case_insensitive
    opt = compiled.opt

    # Simulate while loop
    for _ in range(text_len + 2):
        if maxsplit > 0 and splits_found >= maxsplit:
            break

        regs = search_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive, opt = opt)
        if not regs:
            break

        match_start = regs[0]
        match_end = regs[1]

        if match_start == -1:
            break

        # Append text before match
        res_parts += [text[last_idx:match_start]]

        # If capturing groups, append them too (Python behavior)
        if group_count > 0:
            for i in range(1, group_count + 1):
                s = regs[i * 2]
                e = regs[i * 2 + 1]
                if s == -1:
                    res_parts += [None]
                else:
                    res_parts += [text[s:e]]

        last_idx = match_end
        splits_found += 1

        # Advance start_index
        if match_end > match_start:
            start_index = match_end
        else:
            start_index = match_end + 1

        if start_index > text_len:
            break

    res_parts += [text[last_idx:]]
    return res_parts
