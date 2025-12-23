"VM for Starlark Regex Engine."

load(
    "//lib/private:constants.bzl",
    "MAX_GROUP_NAME_LEN",
    "OP_ANCHOR_END",
    "OP_ANCHOR_LINE_END",
    "OP_ANCHOR_LINE_START",
    "OP_ANCHOR_START",
    "OP_ANY",
    "OP_ANY_NO_NL",
    "OP_CHAR",
    "OP_CHAR_I",
    "OP_GREEDY_LOOP",
    "OP_GREEDY_LOOP_I",
    "OP_JUMP",
    "OP_MATCH",
    "OP_NOT_WORD_BOUNDARY",
    "OP_SAVE",
    "OP_SET",
    "OP_SET_I",
    "OP_SPLIT",
    "OP_STRING",
    "OP_STRING_I",
    "OP_WORD_BOUNDARY",
    "ORD_LOOKUP",
)

# Types
_STRING_TYPE = type("")

_WORD_CHARS = {
    "a": True,
    "b": True,
    "c": True,
    "d": True,
    "e": True,
    "f": True,
    "g": True,
    "h": True,
    "i": True,
    "j": True,
    "k": True,
    "l": True,
    "m": True,
    "n": True,
    "o": True,
    "p": True,
    "q": True,
    "r": True,
    "s": True,
    "t": True,
    "u": True,
    "v": True,
    "w": True,
    "x": True,
    "y": True,
    "z": True,
    "A": True,
    "B": True,
    "C": True,
    "D": True,
    "E": True,
    "F": True,
    "G": True,
    "H": True,
    "I": True,
    "J": True,
    "K": True,
    "L": True,
    "M": True,
    "N": True,
    "O": True,
    "P": True,
    "Q": True,
    "R": True,
    "S": True,
    "T": True,
    "U": True,
    "V": True,
    "W": True,
    "X": True,
    "Y": True,
    "Z": True,
    "0": True,
    "1": True,
    "2": True,
    "3": True,
    "4": True,
    "5": True,
    "6": True,
    "7": True,
    "8": True,
    "9": True,
    "_": True,
}

def _char_in_set(set_struct, c):
    """Checks if character c is in the set_struct."""
    if c in ORD_LOOKUP:
        ord_c = ORD_LOOKUP[c]
        if ord_c < 256:
            res_ascii = set_struct.ascii_bitmap[ord_c]
            if res_ascii:
                return True

    if c in set_struct.lookup:
        return True

    for r_start, r_end in set_struct.ranges:
        if c >= r_start and c <= r_end:
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
# buildifier: disable=function-docstring-args
def _get_epsilon_closure(instructions, input_str, input_len, start_pc, start_regs, current_idx, visited, visited_gen, greedy_cache, input_lower = None):
    reachable = []
    num_inst = len(instructions)

    # Thompson NFA: The first time we reach a PC, it's via the highest priority path.
    stack = [(start_pc, start_regs)]

    # Outer loop handles exploration from stack.
    # Inner loop follows single-thread transitions.
    limit = num_inst * 2 + 100

    # We use a large enough number for the inner loop to cover any possible epsilon chain (max instructions).
    inner_limit = num_inst + 10

    for _ in range(limit):
        if not stack:
            break
        pc, regs = stack.pop()

        # Inner loop to follow a thread's epsilon transitions.
        for _ in range(inner_limit):
            if visited[pc] < visited_gen:
                visited[pc] = visited_gen
            elif visited[pc] == visited_gen:
                visited[pc] = visited_gen + 1
            else:
                continue

            if pc >= num_inst:
                break

            inst = instructions[pc]
            itype = inst[0]

            if itype == OP_JUMP:
                pc = inst[2]
                # Continue loop to process new pc

            elif itype == OP_SPLIT:
                # Add both branches
                pc1 = inst[2]
                pc2 = inst[3]

                # Push lower priority (pc2) first so we follow pc1 (higher priority) immediately
                # DFS order matters for priority
                stack += [(pc2, regs)]
                pc = pc1
                # Continue loop to process pc1

            elif itype == OP_SAVE:
                group_idx = inst[1]
                regs = regs[:]  # Copy on write
                regs[group_idx] = current_idx

                # If this is the end of a capturing group (idx >= 3 and odd), update lastindex
                if group_idx >= 3 and group_idx % 2 == 1:
                    regs[-1] = group_idx // 2
                pc += 1
            elif itype == OP_WORD_BOUNDARY or itype == OP_NOT_WORD_BOUNDARY:
                is_prev_word = (current_idx > 0 and input_str[current_idx - 1] in _WORD_CHARS)
                is_curr_word = (current_idx < input_len and input_str[current_idx] in _WORD_CHARS)
                match = (is_prev_word != is_curr_word) if itype == OP_WORD_BOUNDARY else (is_prev_word == is_curr_word)
                if match:
                    pc += 1
                else:
                    break
            elif itype == OP_ANCHOR_LINE_START:
                if current_idx == 0 or (current_idx > 0 and input_str[current_idx - 1] == "\n"):
                    pc += 1
                else:
                    break
            elif itype == OP_ANCHOR_LINE_END:
                if current_idx == input_len or (current_idx < input_len and input_str[current_idx] == "\n"):
                    pc += 1
                else:
                    break
            elif itype == OP_ANCHOR_START:
                if current_idx == 0:
                    pc += 1
                else:
                    break
            elif itype == OP_ANCHOR_END:
                if current_idx == input_len:
                    pc += 1
                else:
                    break
            elif itype == OP_MATCH:
                reachable += [(pc, regs)]
                break  # A match is found, this path is done.
            elif itype == OP_GREEDY_LOOP or itype == OP_GREEDY_LOOP_I:
                # Optimized x* loop logic with Cache
                chars = inst[1]
                match_len = 0

                # Check cache
                last_end = greedy_cache.get(pc, -1)

                if last_end >= current_idx:
                    match_len = last_end - current_idx
                else:
                    # Compute and cache
                    if itype == OP_GREEDY_LOOP_I and input_lower != None:
                        current_slice = input_lower[current_idx:]
                    else:
                        current_slice = input_str[current_idx:]

                    stripped = current_slice.lstrip(chars)
                    match_len = len(current_slice) - len(stripped)
                    greedy_cache[pc] = current_idx + match_len

                if match_len == 0:
                    # Epsilon transition to Exit
                    pc = inst[2]
                    # Continue loop to process new pc

                else:
                    # Consuming state.
                    # It stops epsilon expansion.
                    # We add it to reachable and BREAK the inner loop.
                    reachable += [(pc, regs)]
                    break
            else:
                # Consuming instruction (CHAR, SET etc)
                # Add to reachable and stop
                reachable += [(pc, regs)]
                break

    return reachable

# buildifier: disable=list-append
# buildifier: disable=list-append
def _process_batch(instructions, batch, input_str, current_idx, input_len, input_lower):
    """Processes a batch of threads against the current character.

    batch is a list of (pc, regs) in priority order.
    Returns (next_threads_list, best_match_regs).
    """
    next_threads_list = []
    next_threads_dict = {}
    best_match_regs = None

    char = input_str[current_idx] if current_idx < input_len else None
    char_lower = input_lower[current_idx] if input_lower != None and current_idx < input_len else None

    for pc, regs, skip_idx in batch:
        if skip_idx > current_idx:
            # Still skipping due to previous OP_STRING match.
            # Just pass it along while maintaining priority.
            if pc not in next_threads_dict:
                next_threads_dict[pc] = True
                next_threads_list += [(pc, regs, skip_idx)]
            continue

        inst = instructions[pc]
        itype = inst[0]

        if itype == OP_MATCH:
            best_match_regs = regs
            break

        if char == None and itype != OP_MATCH:
            continue

        match_found = False
        if itype == OP_CHAR:
            match_found = (inst[1] == char)
        elif itype == OP_CHAR_I:
            match_found = (inst[1] == char_lower)
        elif itype == OP_STRING:
            s = inst[1]
            if input_str.startswith(s, current_idx):
                match_len = len(s)
                next_pc = pc + 1
                if next_pc not in next_threads_dict:
                    next_threads_dict[next_pc] = True
                    next_threads_list += [(next_pc, regs, current_idx + match_len)]
                continue
        elif itype == OP_STRING_I:
            s = inst[1]

            if input_lower != None:
                if input_lower.startswith(s, current_idx):
                    match_len = len(s)
                    next_pc = pc + 1
                    if next_pc not in next_threads_dict:
                        next_threads_dict[next_pc] = True
                        next_threads_list += [(next_pc, regs, current_idx + match_len)]
                    continue
            else:
                # Fallback if no input_lower (shouldn't happen if properly flagged)
                # But execute handles it.
                pass
        elif itype == OP_ANY:
            match_found = True
        elif itype == OP_ANY_NO_NL:
            match_found = (char != "\n")
        elif itype == OP_SET:
            set_struct, is_negated = inst[1]
            if char in ORD_LOOKUP:
                match_found = (set_struct.ascii_bitmap[ORD_LOOKUP[char]] != is_negated)
            else:
                match_found = (_char_in_set(set_struct, char) != is_negated)
        elif itype == OP_SET_I:
            set_struct, is_negated = inst[1]
            if char_lower in ORD_LOOKUP:
                match_found = (set_struct.ascii_bitmap[ORD_LOOKUP[char_lower]] != is_negated)
            else:
                match_found = (_char_in_set(set_struct, char_lower) != is_negated)
        elif itype == OP_GREEDY_LOOP:
            match_found = (char in inst[1])
        elif itype == OP_GREEDY_LOOP_I:
            match_found = (char_lower in inst[1])

        if match_found:
            next_pc = pc
            if itype != OP_GREEDY_LOOP and itype != OP_GREEDY_LOOP_I:
                next_pc = pc + 1

            if next_pc not in next_threads_dict:
                next_threads_dict[next_pc] = True
                next_threads_list += [(next_pc, regs, current_idx + 1)]

    return next_threads_list, best_match_regs

# buildifier: disable=list-append
def execute(instructions, input_str, num_regs, start_index = 0, initial_regs = None, anchored = False, has_case_insensitive = False):
    """Executes the bytecode on the input string.

    Args:
      instructions: Bytecode instructions.
      input_str: Input string.
      num_regs: Number of registers.
      start_index: Start index.
      initial_regs: Initial registers.
      anchored: Whether the match is anchored.
      has_case_insensitive: Whether the match is case insensitive.

    Returns:
      A list of registers (start/end indices) or None.
    """
    if initial_regs == None:
        initial_regs = [-1] * (num_regs + 1)

    input_len = len(input_str)
    input_lower = input_str.lower() if has_case_insensitive else None

    visited = [0] * len(instructions)
    visited_gen = 0
    greedy_cache = {}

    current_threads = [(0, initial_regs, 0)]
    best_match_regs = None

    for char_idx in range(start_index, input_len + 1):
        # Expand epsilon closure for current threads
        visited_gen += 3
        expanded_batch = []

        for s_pc, s_regs, s_skip in current_threads:
            if s_skip > char_idx:
                # Still skipping. Maintain priority.
                expanded_batch += [(s_pc, s_regs, s_skip)]
                continue

            closure = _get_epsilon_closure(instructions, input_str, input_len, s_pc, s_regs, char_idx, visited, visited_gen, greedy_cache, input_lower = input_lower)
            for c_pc, c_regs in closure:
                expanded_batch += [(c_pc, c_regs, char_idx)]

        if not anchored and char_idx <= input_len:
            if visited[0] < visited_gen + 2:
                closure0 = _get_epsilon_closure(instructions, input_str, input_len, 0, initial_regs[:], char_idx, visited, visited_gen, greedy_cache, input_lower = input_lower)
                for c_pc, c_regs in closure0:
                    expanded_batch += [(c_pc, c_regs, char_idx)]

        if not expanded_batch and anchored:
            break

        next_threads = []
        batch_match = None

        if expanded_batch:
            next_threads, batch_match = _process_batch(
                instructions,
                expanded_batch,
                input_str,
                char_idx,
                input_len,
                input_lower,
            )

        if batch_match:
            new_regs = batch_match
            new_start = new_regs[0]

            # Leftmost priority
            if best_match_regs == None or new_start < best_match_regs[0]:
                best_match_regs = new_regs
            elif new_start == best_match_regs[0]:
                # For same start, Thompson NFA naturally finds matches in priority order.
                # However, since we iterate character by character, we might hit multiple
                # matches at different indices for the same start.
                # Standard behavior is to take the LONGEST for greedy.
                # Since char_idx is increasing, we just overwrite.
                best_match_regs = new_regs

        current_threads = next_threads

    return best_match_regs

# buildifier: disable=list-append
def expand_replacement(repl, match_str, groups, named_groups = {}):
    """Expands backreferences in replacement string.

    Args:
      repl: Replacement string.
      match_str: The full matched string.
      groups: Tuple of captured groups.
      named_groups: Map of group names to IDs.

    Returns:
      The expanded replacement string.
    """

    # Simple implementation: replace \1, \2, etc.
    # Starlark doesn't have re.sub inside itself, so we iterate manually.
    res_parts = []
    skip = 0
    repl_len = len(repl)
    for i in range(repl_len):
        if skip > 0:
            skip -= 1
            continue

        c = repl[i]
        if c == "\\" and i + 1 < repl_len:
            next_c = repl[i + 1]
            if next_c >= "0" and next_c <= "9":
                gid = int(next_c)
                if gid == 0:
                    res_parts += [match_str]
                elif gid <= len(groups):
                    val = groups[gid - 1]
                    if val != None:
                        res_parts += [val]
                skip = 1
                continue
            elif next_c == "g" and i + 2 < repl_len and repl[i + 2] == "<":
                # Named group \g<name>
                start_name = i + 3
                end_name = -1
                for k in range(start_name, min(start_name + MAX_GROUP_NAME_LEN, repl_len)):
                    if repl[k] == ">":
                        end_name = k
                        break

                if end_name != -1:
                    name = repl[start_name:end_name]
                    if name in named_groups:
                        gid = named_groups[name]
                        if gid <= len(groups):
                            val = groups[gid - 1]
                            if val != None:
                                res_parts += [val]
                        skip = end_name - i
                        continue

        res_parts += [c]
    return "".join(res_parts)

def search_regs(bytecode, text, group_count, start_index = 0, has_case_insensitive = False):
    num_regs = (group_count + 1) * 2
    return execute(bytecode, text, num_regs, start_index = start_index, anchored = False, has_case_insensitive = has_case_insensitive)

def match_regs(bytecode, text, group_count, start_index = 0, has_case_insensitive = False):
    num_regs = (group_count + 1) * 2
    return execute(bytecode, text, num_regs, start_index = start_index, anchored = True, has_case_insensitive = has_case_insensitive)

def fullmatch_regs(bytecode, text, group_count, start_index = 0, has_case_insensitive = False):
    """Executes a full match returning registers.

    Args:
      bytecode: The bytecode.
      text: The text.
      group_count: Number of groups.
      start_index: Start index.
      has_case_insensitive: CI flag.

    Returns:
      List of registers (start/end indices) or None.
    """
    num_regs = (group_count + 1) * 2
    regs = execute(bytecode, text, num_regs, start_index = start_index, anchored = True, has_case_insensitive = has_case_insensitive)
    if regs and regs[1] != len(text):
        return None
    return regs

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

    TODO: Convert this to a struct when migrating to Bazel rules (which support structs).
    """

    def group(n = 0):
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

    def span(n = 0):
        if type(n) == _STRING_TYPE:
            if n in compiled.named_groups:
                n = compiled.named_groups[n]
            else:
                fail("IndexError: no such group")

        if n < 0 or n > compiled.group_count:
            fail("IndexError: no such group")
        return (regs[n * 2], regs[n * 2 + 1])

    def start(n = 0):
        return span(n)[0]

    def end(n = 0):
        return span(n)[1]

    lastindex = regs[-1]
    if lastindex == -1:
        lastindex = None

    lastgroup = None
    if lastindex != None:
        for name, gid in compiled.named_groups.items():
            if gid == lastindex:
                lastgroup = name
                break

    return struct(
        group = group,
        groups = groups,
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

def search_bytecode(bytecode, text, named_groups, group_count, start_index = 0, has_case_insensitive = False, opt = None):
    """Executes a search using bytecode.

    Args:
      bytecode: The bytecode.
      text: The text.
      named_groups: Named groups map.
      group_count: Number of groups.
      start_index: Start index.
      has_case_insensitive: CI flag.
      opt: Optimization data.

    Returns:
      A MatchObject or None.
    """

    # Fast path optimization
    if opt and not has_case_insensitive:
        if opt.is_anchored_start:
            # If anchored at start, search is just match
            return match_bytecode(bytecode, text, named_groups, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive, opt = opt)

        if opt.is_anchored_end:
            # Case: ...sets...suffix$
            if text.endswith(opt.suffix):
                # Work backwards from the suffix
                before_suffix_idx = len(text) - len(opt.suffix)

                # Use rstrip to find where the greedy set starts
                greedy_start = before_suffix_idx
                if opt.greedy_set_chars != None:
                    prefix_plus_middle = text[:before_suffix_idx]
                    stripped = prefix_plus_middle.rstrip(opt.greedy_set_chars)
                    greedy_start = len(stripped)

                # else: no greedy_set_chars

                # Check prefix_set_chars (one char)
                # Removed this block, as the logic here appears to incorrectly handle cases where
                # opt.prefix is empty and prefix_set_chars describes the start of the greedy part.
                # The greedy_start calculation from rstrip is sufficient in such scenarios.
                match_start = greedy_start
                prefix_ok = True

                # Check prefix literal
                if prefix_ok:
                    if text[:match_start].endswith(opt.prefix):
                        match_start -= len(opt.prefix)

                        regs = [-1] * ((group_count + 1) * 2 + 1)
                        regs[0] = match_start
                        regs[1] = len(text)
                        compiled = struct(
                            bytecode = bytecode,
                            named_groups = named_groups,
                            group_count = group_count,
                            pattern = None,
                            has_case_insensitive = has_case_insensitive,
                            opt = opt,
                        )
                        return MatchObject(text, regs, compiled, start_index, len(text))

        # General case search optimization: skipping to prefix or suffix
        if opt.prefix != "":
            start_off = start_index

            # We can use find() to skip to the first potential match
            for _ in range(len(text)):  # Loop for find() calls
                found_idx = text.find(opt.prefix, start_off)
                if found_idx == -1:
                    break

                # For unanchored search with prefix literal, simple skip:
                regs = match_regs(bytecode, text, group_count, start_index = found_idx, has_case_insensitive = has_case_insensitive)
                if regs:
                    compiled = struct(
                        bytecode = bytecode,
                        named_groups = named_groups,
                        group_count = group_count,
                        pattern = None,
                        has_case_insensitive = has_case_insensitive,
                        opt = opt,
                    )
                    return MatchObject(text, regs, compiled, start_index, len(text))

                # If match failed at found_idx, skip it and look for next prefix
                start_off = found_idx + 1
                if start_off > len(text):
                    break
        elif opt.suffix != "":
            start_off = start_index
            for _ in range(len(text)):
                found_idx = text.find(opt.suffix, start_off)
                if found_idx == -1:
                    break

                # The leftmost match must start after start_index.
                search_start = found_idx
                if opt.greedy_set_chars != None:
                    # Find furthest back we can go with these chars from this suffix point
                    prefix_data = text[start_index:found_idx]
                    stripped = prefix_data.rstrip(opt.greedy_set_chars)
                    search_start = start_index + len(stripped)

                if opt.prefix_set_chars != None:
                    if search_start > start_index and text[search_start - 1] in opt.prefix_set_chars:
                        search_start -= 1

                # Now try a real search starting at search_start
                regs = match_regs(bytecode, text, group_count, start_index = search_start, has_case_insensitive = has_case_insensitive)
                if regs:
                    compiled = struct(
                        bytecode = bytecode,
                        named_groups = named_groups,
                        group_count = group_count,
                        pattern = None,
                        has_case_insensitive = has_case_insensitive,
                        opt = opt,
                    )
                    return MatchObject(text, regs, compiled, start_index, len(text))

                # If no match found yet, move past this suffix
                start_off = found_idx + 1
                if start_off > len(text):
                    break

            return None

    regs = search_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive)
    if not regs:
        return None
    compiled = struct(
        bytecode = bytecode,
        named_groups = named_groups,
        group_count = group_count,
        pattern = None,
        has_case_insensitive = has_case_insensitive,
        opt = opt,
    )
    return MatchObject(text, regs, compiled, start_index, len(text))

def match_bytecode(bytecode, text, named_groups, group_count, start_index = 0, has_case_insensitive = False, opt = None):
    """Executes a match using bytecode.

    Args:
      bytecode: The bytecode.
      text: The text.
      named_groups: Named groups map.
      group_count: Number of groups.
      start_index: Start index.
      has_case_insensitive: CI flag.
      opt: Optimization data.

    Returns:
      A MatchObject or None.
    """

    # Fast path optimization
    if opt and not has_case_insensitive:
        # Simple anchored prefix match
        if text.startswith(opt.prefix, start_index):
            match_end = start_index + len(opt.prefix)
            fast_path_ok = True

            # 1. Match prefix_set_chars (exactly once)
            if opt.prefix_set_chars != None:
                if match_end < len(text) and text[match_end] in opt.prefix_set_chars:
                    match_end += 1
                else:
                    fast_path_ok = False

            # 2. Match greedy_set_chars and suffix
            if fast_path_ok:
                if opt.is_anchored_end:
                    # Must match suffix at the end and greedy_set in between
                    if text.endswith(opt.suffix):
                        middle_start = match_end
                        middle_end = len(text) - len(opt.suffix)
                        if middle_end >= middle_start:
                            if opt.greedy_set_chars != None:
                                middle = text[middle_start:middle_end]
                                if len(middle.lstrip(opt.greedy_set_chars)) == 0:
                                    match_end = len(text)
                                else:
                                    fast_path_ok = False
                            elif middle_start == middle_end:
                                match_end = len(text)
                            else:
                                fast_path_ok = False
                        else:
                            fast_path_ok = False
                    else:
                        fast_path_ok = False
                else:
                    # Not anchored at end
                    if opt.greedy_set_chars != None:
                        rest = text[match_end:]

                        # If there is a suffix, we only support it in the fast path
                        # if it's anchored at the end (handled above) or if it's empty.
                        # Greedy match the rest.
                        if opt.suffix == "":
                            stripped = rest.lstrip(opt.greedy_set_chars)
                            match_end += len(rest) - len(stripped)
                        else:
                            # Complex case: ^\d+abc (not anchored at end)
                            # Fast path only if greedy set and suffix are disjoint?
                            # For now, let's bail on fast path if there is a non-anchored suffix
                            # because we can't easily tell where it should start without backtracking.
                            fast_path_ok = False
                    else:
                        # No greedy set, just prefix(+set) and suffix
                        if text[match_end:].startswith(opt.suffix):
                            match_end += len(opt.suffix)
                        else:
                            fast_path_ok = False

            if fast_path_ok:
                regs = [-1] * ((group_count + 1) * 2 + 1)
                regs[0] = start_index
                regs[1] = match_end
                compiled = struct(
                    bytecode = bytecode,
                    named_groups = named_groups,
                    group_count = group_count,
                    pattern = None,
                    has_case_insensitive = has_case_insensitive,
                    opt = opt,
                )
                return MatchObject(text, regs, compiled, start_index, len(text))

    regs = match_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive)
    if not regs:
        return None
    compiled = struct(
        bytecode = bytecode,
        named_groups = named_groups,
        group_count = group_count,
        pattern = None,
        has_case_insensitive = has_case_insensitive,
        opt = opt,
    )
    return MatchObject(text, regs, compiled, start_index, len(text))

def fullmatch_bytecode(bytecode, text, named_groups, group_count, start_index = 0, has_case_insensitive = False, opt = None):
    """Executes a full match using bytecode.

    Args:
      bytecode: The bytecode.
      text: The text.
      named_groups: Named groups map.
      group_count: Number of groups.
      start_index: Start index.
      has_case_insensitive: CI flag.
      opt: Optimization data.

    Returns:
      A MatchObject or None.
    """

    # Fast path optimization
    if opt and not has_case_insensitive:
        # fullmatch() MUST match the entire string from start_index.
        # So it behaves like it has an implicit $ anchor.
        if text.startswith(opt.prefix, start_index) and text.endswith(opt.suffix):
            match_end = start_index + len(opt.prefix)
            fast_path_ok = True

            if opt.prefix_set_chars != None:
                if match_end < len(text) and text[match_end] in opt.prefix_set_chars:
                    match_end += 1
                else:
                    fast_path_ok = False

            if fast_path_ok:
                middle_start = match_end
                middle_end = len(text) - len(opt.suffix)
                if middle_end >= middle_start:
                    if opt.greedy_set_chars != None:
                        middle = text[middle_start:middle_end]
                        if len(middle.lstrip(opt.greedy_set_chars)) == 0:
                            match_end = len(text)
                        else:
                            fast_path_ok = False
                    elif middle_start == middle_end:
                        match_end = len(text)
                    else:
                        fast_path_ok = False
                else:
                    fast_path_ok = False

            if fast_path_ok and match_end == len(text):
                regs = [-1] * ((group_count + 1) * 2 + 1)
                regs[0] = start_index
                regs[1] = match_end
                compiled = struct(
                    bytecode = bytecode,
                    named_groups = named_groups,
                    group_count = group_count,
                    pattern = None,
                    has_case_insensitive = has_case_insensitive,
                    opt = opt,
                )
                return MatchObject(text, regs, compiled, start_index, len(text))

    regs = fullmatch_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive)
    if not regs:
        return None
    compiled = struct(
        bytecode = bytecode,
        named_groups = named_groups,
        group_count = group_count,
        pattern = None,
        has_case_insensitive = has_case_insensitive,
        opt = opt,
    )
    return MatchObject(text, regs, compiled, start_index, len(text))
