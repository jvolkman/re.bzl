"VM for Starlark Regex Engine."

load(
    "//re/private:constants.bzl",
    "CHR_LOOKUP",
    "OP_ANCHOR_END",
    "OP_ANCHOR_LINE_END",
    "OP_ANCHOR_LINE_START",
    "OP_ANCHOR_START",
    "OP_ANY",
    "OP_ANY_NO_NL",
    "OP_CHAR",
    "OP_EPSILON_START",
    "OP_GREEDY_LOOP",
    "OP_JUMP",
    "OP_MATCH",
    "OP_NEG_GREEDY_LOOP",
    "OP_NOT_WORD_BOUNDARY",
    "OP_SAVE",
    "OP_SET",
    "OP_SPLIT",
    "OP_STRING",
    "OP_UNGREEDY_LOOP",
    "OP_WORD_BOUNDARY",
    "ORD_LOOKUP",
)

# Windowed strips copy the input one window at a time instead of s[start:],
# which would cost O(len(s)) per call, and O(N^2) over a scan of a large input.
# Windows start small, since most runs are short (the unanchored search
# prefilter strips once per match), and grow 4x per step up to
# _MAX_WINDOW_SIZE, so that long runs take few steps.
_MIN_WINDOW_SIZE = 64
_MAX_WINDOW_SIZE = 65536

def _windowed_lstrip(s, chars, start, end = None, lower = False):
    """Lstrips chars from s[start:end] using windowing to avoid large copies.

    If lower is True, each window is lowercased before stripping.
    """
    if end == None:
        end = len(s)
    if start >= end:
        return 0
    pos = start
    size = _MIN_WINDOW_SIZE
    single = len(chars) == 1 and not lower
    if single:
        if s[pos] != chars:
            return 0
        run = chars * size
        for _ in range((end - start) // _MIN_WINDOW_SIZE + 2):
            if pos >= end:
                break
            rem = end - pos
            if rem < size:
                if s.startswith(run[:rem], pos):
                    return end - start
                window = s[pos:end]
                stripped = window.lstrip(chars)
                return pos - start + len(window) - len(stripped)
            if s.startswith(run, pos):
                pos += size
                if size < _MAX_WINDOW_SIZE:
                    size *= 4
                    run = run + run + run + run
                continue
            window = s[pos:pos + size]
            stripped = window.lstrip(chars)
            return pos - start + len(window) - len(stripped)
        return pos - start

    for _ in range((end - start) // _MIN_WINDOW_SIZE + 2):
        if pos >= end:
            break
        stop = pos + size
        if stop > end:
            stop = end
        window = s[pos:stop]
        if lower:
            window = window.lower()
        stripped = window.lstrip(chars)
        pos += len(window) - len(stripped)
        if stripped:
            break
        if size < _MAX_WINDOW_SIZE:
            size *= 4
    return pos - start

def _windowed_rstrip(s, chars, end, min_start = 0):
    """Rstrips chars from s[min_start:end] using windowing to avoid large copies."""
    if end <= min_start:
        return 0
    pos = end
    size = _MIN_WINDOW_SIZE
    if len(chars) == 1:
        if s[pos - 1] != chars:
            return 0
        run = chars * size
        for _ in range((end - min_start) // _MIN_WINDOW_SIZE + 2):
            if pos <= min_start:
                break
            rem = pos - min_start
            if rem < size:
                if s.startswith(run[:rem], min_start):
                    return end - min_start
                window = s[min_start:pos]
                stripped = window.rstrip(chars)
                return end - pos + len(window) - len(stripped)
            start = pos - size
            if s.startswith(run, start):
                pos = start
                if size < _MAX_WINDOW_SIZE:
                    size *= 4
                    run = run + run + run + run
                continue
            window = s[start:pos]
            stripped = window.rstrip(chars)
            return end - pos + len(window) - len(stripped)
        return end - pos

    for _ in range((end - min_start) // _MIN_WINDOW_SIZE + 2):
        if pos <= min_start:
            break
        start = pos - size
        if start < min_start:
            start = min_start
        window = s[start:pos]
        stripped = window.rstrip(chars)
        pos -= len(window) - len(stripped)
        if stripped:
            break
        if size < _MAX_WINDOW_SIZE:
            size *= 4
    return end - pos

def _scan_negated_fwd(s, stop_chars, complement, start, end):
    """Returns length of prefix of s[start:end] containing no char in stop_chars."""
    if start >= end:
        return 0
    if len(stop_chars) == 1:
        idx = s.find(stop_chars, start, end)
        return (idx - start) if idx != -1 else (end - start)
    if complement == None:
        best = end
        for c in stop_chars.elems():
            idx = s.find(c, start, best)
            if idx != -1:
                best = idx
                if best == start:
                    return 0
        return best - start

    # Large negated set (e.g. \D, \W): strip ASCII complement in windows,
    # stepping past any non-ASCII char (>255) which matches the negated set.
    pos = start
    for _ in range(end - start + 1):
        if pos >= end:
            break
        pos += _windowed_lstrip(s, complement, pos, end)
        if pos >= end or s[pos] in stop_chars:
            break
        pos += 1
    return pos - start

def _scan_negated_bwd(s, stop_chars, complement, end, min_start = 0):
    """Returns length of suffix of s[min_start:end] containing no char in stop_chars."""
    if end <= min_start:
        return 0
    if len(stop_chars) == 1:
        idx = s.rfind(stop_chars, min_start, end)
        return (end - idx - 1) if idx != -1 else (end - min_start)
    if complement == None:
        best = min_start
        for c in stop_chars.elems():
            idx = s.rfind(c, best, end)
            if idx != -1:
                best = idx + 1
                if best == end:
                    return 0
        return end - best

    pos = end
    for _ in range(end - min_start + 1):
        if pos <= min_start:
            break
        pos -= _windowed_rstrip(s, complement, pos, min_start)
        if pos <= min_start or s[pos - 1] in stop_chars:
            break
        pos -= 1
    return end - pos

# Types
_STRING_TYPE = type("")

_WORD_CHARS = {c: True for c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".elems()}

def _char_in_set(set_struct, c):
    """Checks if character c is in a complex set_struct (with negated POSIX classes)."""
    if set_struct.ascii_bitmap != None and c in ORD_LOOKUP:
        if set_struct.ascii_bitmap[ORD_LOOKUP[c]]:
            return True

    if c in set_struct.lookup:
        return True

    for pset in set_struct.negated_posix:
        # pset is a list of (start, end) tuples. Character must NOT be in this pset.
        in_pset = False
        for r_start, r_end in pset:
            if c >= r_start and c <= r_end:
                in_pset = True
                break
        if not in_pset:
            return True

    return False

# buildifier: disable=list-append
def execute(instructions, input_str, num_regs, start_index = 0, end_index = None, initial_regs = None, anchored = False, has_case_insensitive = False, input_lower = None, require_end = False, first_skip = None, must_advance = False, visit_limit = 2):
    """Executes the bytecode on the input string.

    Args:
      instructions: Bytecode instructions.
      input_str: Input string.
      num_regs: Number of registers.
      start_index: Start index.
      end_index: End index (optional).
      initial_regs: Initial registers.
      anchored: Whether the match is anchored.
      has_case_insensitive: Whether the match is case insensitive.
      input_lower: Pre-calculated lowercase input string.
      require_end: If True, only matches that end at end_index count (fullmatch).
      first_skip: Optional string of characters that can never begin a match.
      must_advance: If True, an empty match at start_index does not count, but a
        non-empty match starting there does (Python 3.7+ findall/sub/split after
        an empty match).
      visit_limit: How many times the VM may reach a pc at one position (see
        compute_visit_limit).

    Returns:
      A list of registers (start/end indices) or None.
    """
    if initial_regs == None:
        initial_regs = [-1] * (num_regs + 1)

    input_len = len(input_str) if end_index == None else end_index
    lower_on_demand = False
    if input_lower == None and has_case_insensitive:
        if anchored:
            # match()/fullmatch() usually inspect a handful of characters; lowering the
            # whole input on every call would cost O(len(input)).
            lower_on_demand = True
        else:
            input_lower = input_str.lower()

    num_inst = len(instructions)
    visited = [0] * num_inst
    visited_gen = 0
    loop_cache = {}

    # Pre-allocate the bounded iteration range once for epsilon expansion.
    step_range = range(num_inst * visit_limit + 100)

    # Unanchored searches seed a start thread at every position below.
    current_threads = [] if not anchored else [(0, initial_regs, 0)]
    best_match_regs = None
    use_skip = first_skip != None and not anchored
    forbid_empty_at = start_index if must_advance else -1

    char_idx = start_index - 1
    for _ in range(start_index, input_len + 1):
        char_idx += 1
        if char_idx > input_len:
            break

        if use_skip and not current_threads and best_match_regs == None:
            # No live threads: jump to the next position where a match can begin.
            skip = _windowed_lstrip(input_str, first_skip, char_idx, input_len)
            if char_idx + skip >= input_len:
                # No remaining position can begin a (non-empty) match.
                break
            char_idx += skip
        elif current_threads:
            # If all active threads are skipping past char_idx (e.g. from OP_STRING
            # or OP_GREEDY_LOOP), jump directly to min_skip when no new start threads
            # are needed, or skip past first_skip chars up to min_skip otherwise.
            min_skip = current_threads[0][2]
            if min_skip > char_idx:
                for _, _, s_skip in current_threads:
                    if s_skip < min_skip:
                        min_skip = s_skip
                if min_skip > char_idx:
                    if anchored or best_match_regs != None:
                        char_idx = min_skip
                        if char_idx > input_len:
                            break
                    elif use_skip:
                        char_idx += _windowed_lstrip(input_str, first_skip, char_idx, min_skip)

        # Leftmost-first semantics: once a match has been found, a thread seeded at a
        # later start position can never win, so stop seeding new start positions.
        # Also skip seeding at characters that can never begin a match.
        if not anchored and best_match_regs == None:
            if first_skip == None or (char_idx < input_len and input_str[char_idx] not in first_skip):
                current_threads += [(0, initial_regs, char_idx)]

        if not current_threads:
            if anchored or best_match_regs != None:
                break
            continue

        # Expand epsilon transitions and match against the current character in a single pass.
        visited_gen += visit_limit + 1
        visited_last = visited_gen + visit_limit - 1
        next_threads = []
        next_threads_dict = {}
        batch_match = None

        char = input_str[char_idx] if char_idx < input_len else None
        char_lower = None
        if char != None:
            if input_lower != None:
                char_lower = input_lower[char_idx]
            elif lower_on_demand:
                char_lower = char.lower()
        next_idx = char_idx + 1

        for s_pc, s_regs, s_skip in current_threads:
            if batch_match != None:
                # PRUNING: Once a match is found, no lower-priority thread can win.
                break

            if s_skip > char_idx:
                # Still skipping due to a previous OP_STRING or OP_GREEDY_LOOP match.
                key = s_pc if s_skip == next_idx else (s_pc, s_skip)
                if key not in next_threads_dict:
                    next_threads_dict[key] = True
                    next_threads += [(s_pc, s_regs, s_skip)]
                continue

            # Lazily allocate stack only when an OP_SPLIT / OP_UNGREEDY_LOOP forks.
            stack = None
            pc = s_pc
            regs = s_regs
            for _ in step_range:
                for _ in step_range:
                    if visited[pc] < visited_gen:
                        visited[pc] = visited_gen
                    elif visited[pc] < visited_last:
                        visited[pc] += 1
                    else:
                        break

                    inst = instructions[pc]
                    itype = inst[0]

                    if itype < OP_EPSILON_START:
                        if itype == OP_MATCH:
                            if require_end and char_idx != input_len:
                                break
                            if char_idx == forbid_empty_at:
                                break
                            batch_match = regs
                            break

                        if char == None:
                            break

                        match_found = False
                        if itype == OP_CHAR:
                            check_char = char_lower if inst[2] else char
                            match_found = (inst[1] == check_char)
                        elif itype == OP_SET:
                            set_struct = inst[1]
                            c_check = char_lower if inst[2] else char
                            if set_struct.is_simple:
                                match_found = ((c_check in set_struct.lookup) != inst[3])
                            else:
                                match_found = (_char_in_set(set_struct, c_check) != inst[3])
                        elif itype == OP_STRING:
                            s = inst[1]
                            if inst[2]:
                                if input_lower != None:
                                    match_found = input_lower.startswith(s, char_idx)
                                elif lower_on_demand:
                                    match_found = input_str[char_idx:char_idx + len(s)].lower() == s
                            else:
                                match_found = input_str.startswith(s, char_idx)
                            if match_found:
                                resume_idx = char_idx + len(s)
                                if resume_idx <= input_len:
                                    key = (pc + 1, resume_idx)
                                    if key not in next_threads_dict:
                                        next_threads_dict[key] = True
                                        next_threads += [(pc + 1, regs, resume_idx)]
                            break
                        elif itype == OP_ANY:
                            match_found = True
                        elif itype == OP_ANY_NO_NL:
                            match_found = (char != "\n")

                        if match_found:
                            next_pc = pc + 1
                            if next_pc not in next_threads_dict:
                                next_threads_dict[next_pc] = True
                                next_threads += [(next_pc, regs, next_idx)]
                        break

                    if itype == OP_SPLIT:
                        pc1 = inst[2]
                        pc2 = inst[3]
                        if inst[1] != None and visited[inst[1]] >= visited_gen:
                            # A marked SPLIT (see _loop_back_mark): exit instead of
                            # starting another iteration after an empty one.
                            pc = pc2 if pc1 < pc2 else pc1
                        else:
                            if stack == None:
                                stack = [(pc2, regs)]
                            else:
                                stack += [(pc2, regs)]
                            pc = pc1
                    elif itype == OP_SAVE:
                        group_idx = inst[2]
                        regs = regs[:]  # Copy on write
                        regs[group_idx] = char_idx
                        if group_idx >= 3 and group_idx % 2 == 1:
                            regs[-1] = group_idx // 2
                        pc += 1
                    elif itype == OP_JUMP:
                        pc = inst[2]
                    elif itype == OP_WORD_BOUNDARY or itype == OP_NOT_WORD_BOUNDARY:
                        is_prev_word = (char_idx > 0 and input_str[char_idx - 1] in _WORD_CHARS)
                        is_curr_word = (char_idx < input_len and input_str[char_idx] in _WORD_CHARS)
                        if (is_prev_word != is_curr_word) == (itype == OP_WORD_BOUNDARY):
                            pc += 1
                        else:
                            break
                    elif itype == OP_ANCHOR_LINE_START:
                        if char_idx == 0 or input_str[char_idx - 1] == "\n":
                            pc += 1
                        else:
                            break
                    elif itype == OP_ANCHOR_LINE_END:
                        if char_idx == input_len or input_str[char_idx] == "\n":
                            pc += 1
                        else:
                            break
                    elif itype == OP_ANCHOR_START:
                        if char_idx == 0:
                            pc += 1
                        else:
                            break
                    elif itype == OP_ANCHOR_END:
                        if char_idx == input_len:
                            pc += 1
                        else:
                            break
                    elif itype == OP_GREEDY_LOOP:
                        # Optimized disjoint x* loop: skip straight to exit_pc at end of run.
                        last_end = loop_cache.get(pc, -1)
                        if last_end >= char_idx:
                            match_len = last_end - char_idx
                        else:
                            is_ci = inst[3]
                            if is_ci and input_lower != None:
                                match_len = _windowed_lstrip(input_lower, inst[1], char_idx, input_len)
                            else:
                                match_len = _windowed_lstrip(input_str, inst[1], char_idx, input_len, lower = is_ci)
                            loop_cache[pc] = char_idx + match_len

                        if match_len == 0:
                            pc = inst[2]
                        else:
                            exit_pc = inst[2]
                            resume_idx = char_idx + match_len
                            key = exit_pc if resume_idx == next_idx else (exit_pc, resume_idx)
                            if key not in next_threads_dict:
                                next_threads_dict[key] = True
                                next_threads += [(exit_pc, regs, resume_idx)]
                            break
                    elif itype == OP_NEG_GREEDY_LOOP:
                        # Optimized disjoint [^...]* or .* loop: skip straight to exit_pc via find().
                        last_end = loop_cache.get(pc, -1)
                        if last_end >= char_idx:
                            match_len = last_end - char_idx
                        else:
                            stop_chars, complement = inst[1]
                            match_len = _scan_negated_fwd(input_str, stop_chars, complement, char_idx, input_len)
                            loop_cache[pc] = char_idx + match_len

                        if match_len == 0:
                            pc = inst[2]
                        else:
                            exit_pc = inst[2]
                            resume_idx = char_idx + match_len
                            key = exit_pc if resume_idx == next_idx else (exit_pc, resume_idx)
                            if key not in next_threads_dict:
                                next_threads_dict[key] = True
                                next_threads += [(exit_pc, regs, resume_idx)]
                            break
                    elif itype == OP_UNGREEDY_LOOP:
                        if visited[pc] == visited_gen:
                            # First visit: epsilon exit (higher priority).
                            if stack == None:
                                stack = [(pc, regs)]
                            else:
                                stack += [(pc, regs)]
                            pc = inst[2]
                        else:
                            # Second visit: consume one character if it matches (lower priority).
                            if char != None:
                                c_loop = char_lower if inst[3] else char
                                if c_loop in inst[1] and pc not in next_threads_dict:
                                    next_threads_dict[pc] = True
                                    next_threads += [(pc, regs, next_idx)]
                            break

                if batch_match != None or not stack:
                    break
                pc, regs = stack.pop()

        if batch_match:
            new_start = batch_match[0]
            if best_match_regs == None or new_start <= best_match_regs[0]:
                best_match_regs = batch_match

        current_threads = next_threads

        # All surviving threads have higher priority than the current best match. If none
        # survive, nothing can improve on it.
        if not current_threads and best_match_regs != None:
            break

    return best_match_regs

# Escapes that stand for one character in a replacement template, as in Python.
# (\b is a backspace here, not a word boundary.)
_TEMPLATE_ESCAPES = {
    "a": "\007",
    "b": "\010",
    "f": "\014",
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "v": "\013",
    "\\": "\\",
}

_OCT_DIGITS = "01234567"
_ASCII_LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

# buildifier: disable=list-append
def parse_replacement_template(repl, named_groups = {}, group_count = None):
    """Parses a replacement string into a template of tokens.

    Follows Python's rules:
    - `\\1` … `\\99` and `\\g<N>` refer to groups by number, `\\g<name>` by name,
      and `\\g<0>` to the whole match.
    - `\\0`, and three octal digits such as `\\101`, are octal character codes.
    - `\\n`, `\\t`, `\\\\` etc. stand for single characters.
    - Other escaped ASCII letters are errors; other escaped characters are kept
      with their backslash (`\\-` stays `\\-`).

    Args:
      repl: Replacement string.
      named_groups: Map of group names to IDs.
      group_count: Number of groups in the pattern. If given, a reference to a
        group that doesn't exist is an error.

    Returns:
      A list of tokens (strings for literals, integers for group IDs).
    """
    tokens = []
    current_literal = []
    skip = 0
    repl_len = len(repl)

    for i in range(repl_len):
        if skip > 0:
            skip -= 1
            continue

        c = repl[i]
        if c != "\\":
            current_literal += [c]
            continue

        if i + 1 >= repl_len:
            fail("bad escape (end of pattern) at position %d in replacement %r" % (i, repl))
        next_c = repl[i + 1]
        gid = -1

        if next_c == "g":
            if i + 2 >= repl_len or repl[i + 2] != "<":
                fail("missing < at position %d in replacement %r" % (i + 2, repl))
            start_name = i + 3
            end_name = repl.find(">", start_name)
            if end_name == -1:
                fail("missing >, unterminated name at position %d in replacement %r" % (start_name, repl))
            name = repl[start_name:end_name]
            if not name:
                fail("missing group name at position %d in replacement %r" % (start_name, repl))
            if name.isdigit():
                gid = int(name)
            elif name in named_groups:
                gid = named_groups[name]
            else:
                fail("IndexError: unknown group name %r in replacement %r" % (name, repl))
            skip = end_name - i
        elif next_c == "0":
            # \0 followed by up to two more octal digits.
            end = i + 2
            for k in range(i + 2, min(i + 4, repl_len)):
                if repl[k] not in _OCT_DIGITS:
                    break
                end = k + 1
            current_literal += [CHR_LOOKUP[int(repl[i + 1:end], 8)]]
            skip = end - i - 1
            continue
        elif next_c >= "1" and next_c <= "9":
            # One or two digits are a group number; three octal digits are a character.
            if (i + 3 < repl_len and next_c in _OCT_DIGITS and repl[i + 2] in _OCT_DIGITS and
                repl[i + 3] in _OCT_DIGITS):
                code = int(repl[i + 1:i + 4], 8)
                if code > 255:
                    fail("octal escape value \\%s outside of range 0-0o377 in replacement %r" % (repl[i + 1:i + 4], repl))
                current_literal += [CHR_LOOKUP[code]]
                skip = 3
                continue
            if i + 2 < repl_len and repl[i + 2] >= "0" and repl[i + 2] <= "9":
                gid = int(repl[i + 1:i + 3])
                skip = 2
            else:
                gid = int(next_c)
                skip = 1
        elif next_c in _TEMPLATE_ESCAPES:
            current_literal += [_TEMPLATE_ESCAPES[next_c]]
            skip = 1
            continue
        elif next_c in _ASCII_LETTERS:
            fail("bad escape \\%s at position %d in replacement %r" % (next_c, i, repl))
        else:
            current_literal += [c]
            continue

        if group_count != None and gid > group_count:
            fail("invalid group reference %d at position %d in replacement %r" % (gid, i + 1, repl))

        # Flush literal buffer
        if current_literal:
            tokens += ["".join(current_literal)]
            current_literal = []
        tokens += [gid]

    if current_literal:
        tokens += ["".join(current_literal)]

    return tokens

# buildifier: disable=list-append
def expand_template(template, text, regs):
    """Expands a parsed replacement template directly from text and match registers.

    Args:
      template: List of tokens (strings for literals, ints for group IDs).
      text: The source text.
      regs: Flat register list for the match.

    Returns:
      The expanded replacement string.
    """
    res = []
    for token in template:
        if type(token) == _STRING_TYPE:
            res += [token]
        else:
            s = regs[token * 2]
            if s != -1:
                res += [text[s:regs[token * 2 + 1]]]

    return "".join(res)

def search_regs(bytecode, text, group_count, start_index = 0, end_index = None, has_case_insensitive = False, opt = None, input_lower = None, first_skip = None, must_advance = False, visit_limit = 2):
    """Executes a search returning registers.

    The returned `regs` is a flat list of integers representing [start, end] pairs for each group.
    regs[0] is start of group 0.
    regs[1] is end of group 0.
    regs[2 * n] is start of group n.
    regs[2 * n + 1] is end of group n.
    This flat structure is used for performance to avoid allocating tuple objects.

    Args:
      bytecode: The bytecode.
      text: The text.
      group_count: Number of groups.
      start_index: Start index.
      end_index: End index (optional).
      has_case_insensitive: CI flag.
      opt: Optimization data.
      input_lower: Pre-calculated lowercase input string.
      first_skip: Characters that can never begin a match (see compute_first_skip).
      must_advance: If True, reject an empty match at start_index (the previous
        findall/sub/split match was empty and ended there).
      visit_limit: How many times the VM may reach a pc at one position (see
        compute_visit_limit).

    Returns:
      List of registers (start/end indices) or None.
    """
    effective_len = len(text) if end_index == None else end_index
    anchored_start = (opt and opt.is_anchored_start) or (len(bytecode) > 1 and bytecode[1][0] == OP_ANCHOR_START)

    if anchored_start:
        # `^` (without MULTILINE) only matches at index 0, never at a later
        # start position (e.g. the next findall/sub/split iteration).
        if start_index > 0:
            return None
        if must_advance:
            return execute(bytecode, text, (group_count + 1) * 2, end_index = end_index, anchored = True, has_case_insensitive = has_case_insensitive, input_lower = input_lower, must_advance = True, visit_limit = visit_limit)
        return match_regs(bytecode, text, group_count, start_index = 0, end_index = end_index, has_case_insensitive = has_case_insensitive, opt = opt, input_lower = input_lower, first_skip = first_skip, visit_limit = visit_limit)

    if input_lower == None and has_case_insensitive:
        input_lower = text.lower()

    # Fast path optimization. The fast paths below do not implement must_advance. It
    # is only set after an empty match, which the patterns they handle can produce
    # only at the end of the input, where the general engine is cheap.
    if opt and not must_advance:
        # Only `...prefix [set]* suffix$` and `...prefix [set]+ suffix$` are handled here.
        # (`(?i:[ab])[ab]*` has equal sets but isn't `[ab]+`.)
        prefix_set_is_plus = (opt.prefix_set_chars != None and
                              opt.prefix_set_chars == opt.greedy_set_chars and
                              opt.is_prefix_set_case_insensitive == opt.is_greedy_case_insensitive and
                              opt.is_prefix_set_negated == opt.is_greedy_negated)
        if opt.is_anchored_end and not has_case_insensitive and (opt.prefix_set_chars == None or prefix_set_is_plus):
            # Case: ...sets...suffix$
            if effective_len >= len(opt.suffix) and text.startswith(opt.suffix, effective_len - len(opt.suffix)):
                # Work backwards from the suffix
                before_suffix_idx = effective_len - len(opt.suffix)

                # Scan backwards to find where the greedy set starts
                greedy_start = before_suffix_idx
                if opt.greedy_set_chars != None:
                    if opt.is_greedy_negated:
                        stop_chars, complement = opt.greedy_neg_scan
                        match_len = _scan_negated_bwd(text, stop_chars, complement, before_suffix_idx, start_index + len(opt.prefix))
                    else:
                        match_len = _windowed_rstrip(text, opt.greedy_set_chars, before_suffix_idx, start_index + len(opt.prefix))
                    greedy_start = before_suffix_idx - match_len

                match_start = greedy_start

                # `[set]+` needs at least one character from the set.
                prefix_ok = not prefix_set_is_plus or greedy_start < before_suffix_idx

                # Check prefix literal
                if prefix_ok:
                    if text.endswith(opt.prefix, 0, match_start):
                        match_start -= len(opt.prefix)

                        # A match starting before start_index (e.g. a later findall
                        # iteration) is not a valid result; fall through.
                        if match_start >= start_index:
                            regs = [-1] * ((group_count + 1) * 2 + 1)
                            regs[0] = match_start
                            regs[1] = effective_len
                            return regs

        # General case search optimization: skipping to prefix or suffix
        if opt.prefix != "":
            start_off = start_index
            search_text = input_lower if opt.case_insensitive_prefix else text

            # We can use find() to skip to the first potential match
            for _ in range(len(text)):  # Loop for find() calls
                found_idx = search_text.find(opt.prefix, start_off, effective_len)
                if found_idx == -1:
                    break

                # For unanchored search with prefix literal, simple skip:
                regs = match_regs(bytecode, text, group_count, start_index = found_idx, end_index = end_index, has_case_insensitive = has_case_insensitive, opt = opt, input_lower = input_lower, visit_limit = visit_limit)
                if regs:
                    return regs

                # If match failed at found_idx, skip it and look for next prefix
                start_off = found_idx + 1
                if start_off > effective_len:
                    break

            return None
        elif opt.suffix != "" and (opt.prefix_set_chars == None or opt.greedy_set_chars == None or prefix_set_is_plus):
            # Backing up from the suffix over the loop finds the leftmost start, but in
            # `[set1][set2]*suffix` the set1 character can be inside the loop's run
            # (`[ab][bc]*c` matches "bc" in "ccbc"), so that's left to the NFA.
            search_text = input_lower if opt.is_suffix_case_insensitive else text

            start_off = start_index
            for _ in range(len(text)):
                found_idx = search_text.find(opt.suffix, start_off, effective_len)
                if found_idx == -1:
                    break

                # The leftmost match must start after start_index.
                search_start = found_idx
                if opt.greedy_set_chars != None:
                    if opt.is_greedy_negated:
                        stop_chars, complement = opt.greedy_neg_scan
                        match_len = _scan_negated_bwd(text, stop_chars, complement, found_idx, start_index)
                    else:
                        loop_text = input_lower if opt.is_greedy_case_insensitive else text
                        match_len = _windowed_rstrip(loop_text, opt.greedy_set_chars, found_idx, start_index)
                    search_start = found_idx - match_len

                if opt.prefix_set_chars != None and search_start > start_index:
                    set_text = input_lower if opt.is_prefix_set_case_insensitive else text
                    if (set_text[search_start - 1] in opt.prefix_set_chars) != opt.is_prefix_set_negated:
                        search_start -= 1

                # Now try a real search starting at search_start
                can_bypass = False
                if opt.prefix == "" and opt.prefix_set_chars == None:
                    if opt.is_suffix_disjoint:
                        can_bypass = True
                    elif opt.is_ungreedy_loop:
                        if opt.is_greedy_negated:
                            stop_chars, complement = opt.greedy_neg_scan
                            strip_len = _scan_negated_fwd(text, stop_chars, complement, search_start, found_idx)
                        else:
                            loop_text = input_lower if opt.is_greedy_case_insensitive else text
                            strip_len = _windowed_lstrip(loop_text, opt.greedy_set_chars, search_start, found_idx)
                        if search_start + strip_len >= found_idx:
                            can_bypass = True

                # The bypass does not evaluate `$`.
                if can_bypass and opt.is_anchored_end and found_idx + len(opt.suffix) != effective_len:
                    can_bypass = False

                if can_bypass:
                    # Optimization: We know we matched everything up to suffix
                    regs = [-1] * ((group_count + 1) * 2 + 1)
                    regs[0] = search_start
                    regs[1] = found_idx + len(opt.suffix)
                    return regs

                regs = match_regs(bytecode, text, group_count, start_index = search_start, end_index = end_index, has_case_insensitive = has_case_insensitive, opt = opt, input_lower = input_lower, visit_limit = visit_limit)
                if regs:
                    return regs

                # If no match found yet, move past this suffix
                start_off = found_idx + 1
                if start_off > effective_len:
                    break

            return None
        elif opt.suffix == "" and opt.prefix_set_chars != None and not opt.is_anchored_end and first_skip != None:
            # Unanchored `[set]`, `[set]+`, `[^set]+`, or `[set1][set2]*` with no literal prefix/suffix:
            # jump straight to the next candidate via first_skip, then consume any greedy loop.
            pos = start_index
            set_text = input_lower if opt.is_prefix_set_case_insensitive else text
            loop_text = input_lower if opt.is_greedy_case_insensitive else text
            for _ in range(effective_len - start_index + 1):
                if pos >= effective_len:
                    return None
                pos += _windowed_lstrip(text, first_skip, pos, effective_len)
                if pos >= effective_len:
                    return None
                if (set_text[pos] in opt.prefix_set_chars) != opt.is_prefix_set_negated:
                    match_end = pos + 1
                    if opt.greedy_set_chars != None and not opt.is_ungreedy_loop:
                        if opt.is_greedy_negated:
                            stop_chars, complement = opt.greedy_neg_scan
                            match_end += _scan_negated_fwd(text, stop_chars, complement, match_end, effective_len)
                        else:
                            match_end += _windowed_lstrip(loop_text, opt.greedy_set_chars, match_end, effective_len)
                    if group_count == 0:
                        return [pos, match_end, -1]
                    regs = [-1] * ((group_count + 1) * 2 + 1)
                    regs[0] = pos
                    regs[1] = match_end
                    return regs
                pos += 1
            return None

    num_regs = (group_count + 1) * 2
    return execute(bytecode, text, num_regs, start_index = start_index, end_index = end_index, anchored = False, has_case_insensitive = has_case_insensitive, input_lower = input_lower, first_skip = first_skip, must_advance = must_advance, visit_limit = visit_limit)

def match_regs(bytecode, text, group_count, start_index = 0, end_index = None, has_case_insensitive = False, opt = None, input_lower = None, first_skip = None, visit_limit = 2):
    """Executes a match returning registers.

    Args:
      bytecode: The bytecode.
      text: The text.
      group_count: Number of groups.
      start_index: Start index.
      end_index: End index (optional).
      has_case_insensitive: CI flag.
      opt: Optimization data.
      input_lower: Pre-calculated lowercase input string.
      first_skip: Characters that can never begin a match (see compute_first_skip).
      visit_limit: How many times the VM may reach a pc at one position (see
        compute_visit_limit).

    Returns:
      List of registers (start/end indices) or None.
    """
    effective_len = len(text) if end_index == None else end_index

    # O(1) reject: the character at start_index cannot begin a match.
    if first_skip != None and (start_index >= effective_len or text[start_index] in first_skip):
        return None

    # Fast path optimization (the fast path does not evaluate `^`, so it only
    # applies at index 0 for start-anchored patterns).
    if opt and (start_index == 0 or not opt.is_anchored_start):
        # Simple anchored prefix match (lower only the prefix slice if needed,
        # avoiding O(len(text)) lowering on match() calls over large inputs).
        prefix_len = len(opt.prefix)
        prefix_ok = start_index + prefix_len <= effective_len
        if prefix_ok and prefix_len > 0:
            if opt.case_insensitive_prefix:
                if input_lower != None:
                    prefix_ok = input_lower.startswith(opt.prefix, start_index)
                else:
                    prefix_ok = text[start_index:start_index + prefix_len].lower() == opt.prefix
            else:
                prefix_ok = text.startswith(opt.prefix, start_index)

        if prefix_ok:
            match_end = start_index + prefix_len
            fast_path_ok = True

            # 1. Match prefix_set_chars (exactly once)
            if opt.prefix_set_chars != None:
                if match_end < effective_len:
                    c = text[match_end]
                    if opt.is_prefix_set_case_insensitive:
                        c = input_lower[match_end] if input_lower != None else c.lower()
                    if (c in opt.prefix_set_chars) != opt.is_prefix_set_negated:
                        match_end += 1
                    else:
                        fast_path_ok = False
                else:
                    fast_path_ok = False

            # 2. Match greedy_set_chars and suffix. Each part is compared case-insensitively
            # only if that part of the pattern is (see fullmatch_regs).
            if fast_path_ok:
                loop_lower = opt.is_greedy_case_insensitive and input_lower == None
                loop_text = input_lower if (opt.is_greedy_case_insensitive and input_lower != None) else text
                suffix_len = len(opt.suffix)
                if opt.is_anchored_end:
                    # Must match suffix at the end and greedy_set in between
                    suffix_start = effective_len - suffix_len
                    suffix_ok = suffix_start >= match_end
                    if suffix_ok and suffix_len > 0:
                        if opt.is_suffix_case_insensitive:
                            if input_lower != None:
                                suffix_ok = input_lower.startswith(opt.suffix, suffix_start)
                            else:
                                suffix_ok = text[suffix_start:effective_len].lower() == opt.suffix
                        else:
                            suffix_ok = text.startswith(opt.suffix, suffix_start)
                    if suffix_ok:
                        if opt.greedy_set_chars != None:
                            if opt.is_greedy_negated:
                                stop_chars, complement = opt.greedy_neg_scan
                                strip_len = _scan_negated_fwd(text, stop_chars, complement, match_end, suffix_start)
                            else:
                                strip_len = _windowed_lstrip(loop_text, opt.greedy_set_chars, match_end, suffix_start, lower = loop_lower)
                            if match_end + strip_len >= suffix_start:
                                match_end = effective_len
                            else:
                                fast_path_ok = False
                        elif match_end == suffix_start:
                            match_end = effective_len
                        else:
                            fast_path_ok = False
                    else:
                        fast_path_ok = False
                elif suffix_len > 0:
                    # Case: ^a*b (not anchored at end)
                    # Find first occurrence of suffix after match_end.
                    # Only valid for lazy loops, or greedy loops that cannot consume the suffix.
                    if opt.greedy_set_chars != None and not opt.is_ungreedy_loop and not opt.is_suffix_disjoint:
                        fast_path_ok = False
                    found_idx = -1
                    if fast_path_ok:
                        if opt.is_suffix_case_insensitive:
                            if input_lower == None:
                                input_lower = text.lower()
                            found_idx = input_lower.find(opt.suffix, match_end, effective_len)
                        else:
                            found_idx = text.find(opt.suffix, match_end, effective_len)
                    if found_idx != -1:
                        # Check if everything between match_end and found_idx is in greedy_set
                        if opt.greedy_set_chars != None:
                            if opt.is_greedy_negated:
                                stop_chars, complement = opt.greedy_neg_scan
                                strip_len = _scan_negated_fwd(text, stop_chars, complement, match_end, found_idx)
                            else:
                                strip_len = _windowed_lstrip(loop_text, opt.greedy_set_chars, match_end, found_idx, lower = loop_lower)
                            if match_end + strip_len >= found_idx:
                                match_end = found_idx + suffix_len
                            else:
                                fast_path_ok = False
                        elif match_end == found_idx:
                            # No greedy set, suffix must follow prefix immediately
                            match_end = found_idx + suffix_len
                        else:
                            fast_path_ok = False
                    else:
                        fast_path_ok = False
                elif opt.greedy_set_chars != None and not opt.is_ungreedy_loop:
                    # No suffix, not anchored at end: greedy match the rest.
                    # (A lazy loop matches zero iterations here.)
                    if opt.is_greedy_negated:
                        stop_chars, complement = opt.greedy_neg_scan
                        match_end += _scan_negated_fwd(text, stop_chars, complement, match_end, effective_len)
                    else:
                        match_end += _windowed_lstrip(loop_text, opt.greedy_set_chars, match_end, effective_len, lower = loop_lower)

            if fast_path_ok:
                if group_count == 0:
                    return [start_index, match_end, -1]
                regs = [-1] * ((group_count + 1) * 2 + 1)
                regs[0] = start_index
                regs[1] = match_end
                return regs

    num_regs = (group_count + 1) * 2
    return execute(bytecode, text, num_regs, start_index = start_index, end_index = end_index, anchored = True, has_case_insensitive = has_case_insensitive, input_lower = input_lower, visit_limit = visit_limit)

def fullmatch_regs(bytecode, text, group_count, start_index = 0, end_index = None, has_case_insensitive = False, opt = None, input_lower = None, first_skip = None, visit_limit = 2):
    """Executes a full match returning registers.

    Args:
      bytecode: The bytecode.
      text: The text.
      group_count: Number of groups.
      start_index: Start index.
      end_index: End index (optional).
      has_case_insensitive: CI flag.
      opt: Optimization data.
      input_lower: Pre-calculated lowercase input string.
      first_skip: Characters that can never begin a match (see compute_first_skip).
      visit_limit: How many times the VM may reach a pc at one position (see
        compute_visit_limit).

    Returns:
      List of registers (start/end indices) or None.
    """
    effective_len = len(text) if end_index == None else end_index

    # O(1) reject: the character at start_index cannot begin a match.
    if first_skip != None and (start_index >= effective_len or text[start_index] in first_skip):
        return None

    # Fast path optimization (the fast path does not evaluate `^`, so it only
    # applies at index 0 for start-anchored patterns).
    if opt and (start_index == 0 or not opt.is_anchored_start):
        # fullmatch() MUST match the entire string from start_index.
        # Each part is compared case-insensitively only if that part of the pattern is
        # (scoped flags such as `(?i:x)[a-z]+` can mix both).
        prefix_len = len(opt.prefix)
        suffix_len = len(opt.suffix)
        suffix_start = effective_len - suffix_len
        match_end = start_index + prefix_len
        fast_path_ok = match_end <= suffix_start

        if fast_path_ok and prefix_len > 0:
            if opt.case_insensitive_prefix:
                if input_lower != None:
                    fast_path_ok = input_lower.startswith(opt.prefix, start_index)
                else:
                    fast_path_ok = text[start_index:match_end].lower() == opt.prefix
            else:
                fast_path_ok = text.startswith(opt.prefix, start_index)

        if fast_path_ok and suffix_len > 0:
            if opt.is_suffix_case_insensitive:
                if input_lower != None:
                    fast_path_ok = input_lower.startswith(opt.suffix, suffix_start)
                else:
                    fast_path_ok = text[suffix_start:effective_len].lower() == opt.suffix
            else:
                fast_path_ok = text.startswith(opt.suffix, suffix_start)

        if fast_path_ok and opt.prefix_set_chars != None:
            if match_end < suffix_start:
                c = text[match_end]
                if opt.is_prefix_set_case_insensitive:
                    c = input_lower[match_end] if input_lower != None else c.lower()
                if (c in opt.prefix_set_chars) != opt.is_prefix_set_negated:
                    match_end += 1
                else:
                    fast_path_ok = False
            else:
                fast_path_ok = False

        if fast_path_ok:
            if opt.greedy_set_chars != None:
                if opt.is_greedy_negated:
                    stop_chars, complement = opt.greedy_neg_scan
                    strip_len = _scan_negated_fwd(text, stop_chars, complement, match_end, suffix_start)
                else:
                    loop_lower = opt.is_greedy_case_insensitive and input_lower == None
                    loop_text = input_lower if (opt.is_greedy_case_insensitive and input_lower != None) else text
                    strip_len = _windowed_lstrip(loop_text, opt.greedy_set_chars, match_end, suffix_start, lower = loop_lower)
                fast_path_ok = match_end + strip_len >= suffix_start
            else:
                fast_path_ok = match_end == suffix_start

        if fast_path_ok:
            if group_count == 0:
                return [start_index, effective_len, -1]
            regs = [-1] * ((group_count + 1) * 2 + 1)
            regs[0] = start_index
            regs[1] = effective_len
            return regs

    num_regs = (group_count + 1) * 2
    return execute(bytecode, text, num_regs, start_index = start_index, end_index = end_index, anchored = True, has_case_insensitive = has_case_insensitive, input_lower = input_lower, require_end = True, visit_limit = visit_limit)

# buildifier: disable=list-append
def MatchObject(text, regs, compiled, pos, endpos):
    """Constructs a match object with methods.

    Args:
      text: The source text.
      regs: Captured registers.
      compiled: The compiled regex struct.
      pos: The start position of the search.
      endpos: The end position of the search.

    Returns:
      A MatchObject struct.
    """

    def group(n = 0):
        if n == 0:
            return text[regs[0]:regs[1]]
        if type(n) == _STRING_TYPE:
            if n in compiled.named_groups:
                n = compiled.named_groups[n]
            else:
                fail("IndexError: no such group")

        if n < 0 or n > compiled.group_count:
            fail("IndexError: no such group")
        start = regs[n * 2]
        end = regs[n * 2 + 1]
        if start == -1 or end == -1:
            return None
        return text[start:end]

    def groups(default = None):
        res = []
        for i in range(1, compiled.group_count + 1):
            start = regs[i * 2]
            end = regs[i * 2 + 1]
            if start == -1 or end == -1:
                res += [default]
            else:
                res += [text[start:end]]
        return tuple(res)

    def groupdict(default = None):
        res = {}
        for name, i in compiled.named_groups.items():
            start = regs[i * 2]
            end = regs[i * 2 + 1]
            if start == -1 or end == -1:
                res[name] = default
            else:
                res[name] = text[start:end]
        return res

    def span(n = 0):
        if n == 0:
            return (regs[0], regs[1])
        if type(n) == _STRING_TYPE:
            if n in compiled.named_groups:
                n = compiled.named_groups[n]
            else:
                fail("IndexError: no such group")

        if n < 0 or n > compiled.group_count:
            fail("IndexError: no such group")
        return (regs[n * 2], regs[n * 2 + 1])

    def start(n = 0):
        if n == 0:
            return regs[0]
        return span(n)[0]

    def end(n = 0):
        if n == 0:
            return regs[1]
        return span(n)[1]

    lastindex = regs[-1]
    if lastindex == -1:
        lastindex = None

    lastgroup = compiled.gid_to_name.get(lastindex) if lastindex != None else None

    return struct(
        group = group,
        groups = groups,
        groupdict = groupdict,
        span = span,
        start = start,
        end = end,
        string = text,
        re = compiled,
        pos = pos,
        endpos = endpos,
        lastindex = lastindex,
        lastgroup = lastgroup,
    )
