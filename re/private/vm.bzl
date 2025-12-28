"VM for Starlark Regex Engine."

load(
    "//re/private:constants.bzl",
    "MAX_GROUP_NAME_LEN",
    "OP_ANCHOR_END",
    "OP_ANCHOR_LINE_END",
    "OP_ANCHOR_LINE_START",
    "OP_ANCHOR_START",
    "OP_ANY",
    "OP_ANY_NO_NL",
    "OP_CHAR",
    "OP_GREEDY_LOOP",
    "OP_JUMP",
    "OP_MATCH",
    "OP_NOT_WORD_BOUNDARY",
    "OP_SAVE",
    "OP_SET",
    "OP_SPLIT",
    "OP_STRING",
    "OP_UNGREEDY_LOOP",
    "OP_WORD_BOUNDARY",
    "ORD_LOOKUP",
)

# Default window size for windowed string operations.
# Windowing avoids creating massive intermediate string slices, which can
# lead to O(N^2) memory and time behavior in Starlark for large inputs.
_WINDOW_SIZE = 65536

def _windowed_lstrip(s, chars, start):
    """Lstrips chars from s[start:] using windowing to avoid large copies."""
    n = len(s)
    pos = start
    for _ in range(n // _WINDOW_SIZE + 1):
        window = s[pos:pos + _WINDOW_SIZE]
        if not window:
            break
        stripped = window.lstrip(chars)
        match_len = len(window) - len(stripped)
        pos += match_len
        if len(stripped) > 0:
            break
    return pos - start

def _windowed_rstrip(s, chars, end):
    """Rstrips chars from s[:end] using windowing to avoid large copies."""
    pos = end
    for _ in range(end // _WINDOW_SIZE + 1):
        start = max(0, pos - _WINDOW_SIZE)
        window = s[start:pos]
        if not window:
            break
        stripped = window.rstrip(chars)
        match_len = len(window) - len(stripped)
        pos -= match_len
        if len(stripped) > 0:
            break
    return end - pos

# Types
_STRING_TYPE = type("")

_WORD_CHARS = {c: True for c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".elems()}

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
def _get_epsilon_closure(instructions, input_str, input_len, start_pc, start_regs, current_idx, visited, visited_gen, greedy_cache, input_lower = None, word_mask = None):
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
                pc = inst[2]  # arg1 = target
                # Continue loop to process new pc

            elif itype == OP_SPLIT:
                # Add both branches
                pc1 = inst[2]  # arg1
                pc2 = inst[3]  # arg2

                # Push lower priority (pc2) first so we follow pc1 (higher priority) immediately
                # DFS order matters for priority
                stack += [(pc2, regs)]
                pc = pc1
                # Continue loop to process pc1

            elif itype == OP_SAVE:
                group_idx = inst[2]  # arg1 = slot
                regs = regs[:]  # Copy on write
                regs[group_idx] = current_idx

                # If this is the end of a capturing group (idx >= 3 and odd), update lastindex
                if group_idx >= 3 and group_idx % 2 == 1:
                    regs[-1] = group_idx // 2
                pc += 1
            elif itype == OP_WORD_BOUNDARY or itype == OP_NOT_WORD_BOUNDARY:
                if word_mask != None:
                    is_prev_word = (current_idx > 0 and word_mask[current_idx - 1])
                    is_curr_word = (current_idx < input_len and word_mask[current_idx])
                else:
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
            elif itype == OP_GREEDY_LOOP:
                # Optimized x* loop logic with Cache
                chars = inst[1]  # val
                match_len = 0
                is_ci = inst[3]  # arg2 = is_ci

                # Check cache
                last_end = greedy_cache.get(pc, -1)

                if last_end >= current_idx:
                    match_len = last_end - current_idx
                else:
                    # Compute and cache
                    input_to_strip = input_str
                    if is_ci and input_lower != None:
                        input_to_strip = input_lower

                    match_len = _windowed_lstrip(input_to_strip, chars, current_idx)
                    greedy_cache[pc] = current_idx + match_len

                if match_len == 0:
                    # Epsilon transition to Exit
                    pc = inst[2]  # arg1 = exit_pc
                    # Continue loop to process new pc

                else:
                    reachable += [(pc, regs)]
                    break
            elif itype == OP_UNGREEDY_LOOP:
                # Optimized x*? loop logic with Cache
                if visited[pc] == visited_gen:
                    # First visit: Epsilon path (high priority)
                    # Stay in epsilon expansion loop for exit_pc
                    stack += [(pc, regs)]  # Push to stack for second visit (low priority)
                    pc = inst[2]  # arg1 = exit_pc
                else:
                    # Second visit (visited[pc] == visited_gen + 1):
                    # Consuming path (low priority)
                    # Use cache to check if we can consume
                    chars = inst[1]  # val
                    is_ci = inst[3]  # arg2 = is_ci
                    last_end = greedy_cache.get(pc, -1)
                    match_len = 0

                    if last_end >= current_idx:
                        match_len = last_end - current_idx
                    else:
                        # Compute and cache
                        input_to_strip = input_str
                        if is_ci and input_lower != None:
                            input_to_strip = input_lower

                        match_len = _windowed_lstrip(input_to_strip, chars, current_idx)
                        greedy_cache[pc] = current_idx + match_len

                    if match_len > 0:
                        reachable += [(pc, regs)]
                    break

            else:
                # Consuming instruction (CHAR, SET etc)
                # Add to reachable and stop
                reachable += [(pc, regs)]
                break

    return reachable

# buildifier: disable=list-append
def _process_batch(instructions, batch, input_str, current_idx, input_len, input_lower):
    """Processes a batch of threads against the current character.

    batch is a list of (pc, regs, skip_idx) in priority order (index 0 is highest).
    Returns (next_threads_list, best_match_regs, matched_priority_index).
    """
    next_threads_list = []
    next_threads_dict = {}
    best_match_regs = None
    matched_priority_index = -1

    char = input_str[current_idx] if current_idx < input_len else None
    char_lower = input_lower[current_idx] if input_lower != None and current_idx < input_len else None

    # Process in priority order (0 = highest)
    for i in range(len(batch)):
        pc, regs, skip_idx = batch[i]
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
            if best_match_regs == None:
                best_match_regs = regs
                matched_priority_index = i

            # PRUNING: Once a match is found, no lower-priority thread can EVER win
            # for the current or any FUTURE character position (leftmost-priority).
            # We stop processing the current batch AND return the match.
            break

        if char == None and itype != OP_MATCH:
            continue

        match_found = False
        if itype == OP_CHAR:
            check_char = char_lower if inst[2] else char  # arg1 = is_ci
            match_found = (inst[1] == check_char)  # val
        elif itype == OP_STRING:
            s = inst[1]  # val
            if inst[2]:  # arg1 = is_ci
                if input_lower != None:
                    if input_lower.startswith(s, current_idx):
                        match_len = len(s)
                        next_pc = pc + 1
                        if next_pc not in next_threads_dict:
                            next_threads_dict[next_pc] = True
                            next_threads_list += [(next_pc, regs, current_idx + match_len)]
                        continue
            elif input_str.startswith(s, current_idx):
                match_len = len(s)
                next_pc = pc + 1
                if next_pc not in next_threads_dict:
                    next_threads_dict[next_pc] = True
                    next_threads_list += [(next_pc, regs, current_idx + match_len)]
                continue
        elif itype == OP_ANY:
            match_found = True
        elif itype == OP_ANY_NO_NL:
            match_found = (char != "\n")
        elif itype == OP_SET:
            set_struct, is_negated = inst[1]  # val
            is_ci = inst[2]  # arg1 = is_ci
            c_check = char_lower if is_ci else char

            if c_check in ORD_LOOKUP:
                match_found = (set_struct.ascii_bitmap[ORD_LOOKUP[c_check]] != is_negated)
            else:
                match_found = (_char_in_set(set_struct, c_check) != is_negated)
        elif itype == OP_GREEDY_LOOP or itype == OP_UNGREEDY_LOOP:
            is_ci = inst[3]  # arg2 = is_ci
            if is_ci:
                match_found = (char_lower in inst[1])  # val
            else:
                match_found = (char in inst[1])  # val

        if match_found:
            next_pc = pc
            if itype != OP_GREEDY_LOOP and itype != OP_UNGREEDY_LOOP:
                next_pc = pc + 1

            if next_pc not in next_threads_dict:
                next_threads_dict[next_pc] = True
                next_threads_list += [(next_pc, regs, current_idx + 1)]

    return next_threads_list, best_match_regs, matched_priority_index

# buildifier: disable=list-append
def execute(instructions, input_str, num_regs, start_index = 0, end_index = None, initial_regs = None, anchored = False, has_case_insensitive = False, input_lower = None, word_mask = None):
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
      word_mask: Pre-calculated word character mask.

    Returns:
      A list of registers (start/end indices) or None.
    """
    if initial_regs == None:
        initial_regs = [-1] * (num_regs + 1)

    input_original_len = len(input_str)
    input_len = input_original_len if end_index == None else end_index
    if input_lower == None and has_case_insensitive:
        input_lower = input_str.lower()

    # Pre-calculate word mask for boundary checks
    if word_mask == None:
        has_boundary = False
        for inst in instructions:
            if inst[0] == OP_WORD_BOUNDARY or inst[0] == OP_NOT_WORD_BOUNDARY:
                has_boundary = True
                break
        if has_boundary:
            word_mask = [c in _WORD_CHARS for c in input_str.elems()]

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

            closure = _get_epsilon_closure(instructions, input_str, input_len, s_pc, s_regs, char_idx, visited, visited_gen, greedy_cache, input_lower = input_lower, word_mask = word_mask)
            for c_pc, c_regs in closure:
                expanded_batch += [(c_pc, c_regs, char_idx)]

        if not anchored and char_idx <= input_len:
            if visited[0] < visited_gen + 2:
                closure0 = _get_epsilon_closure(instructions, input_str, input_len, 0, initial_regs[:], char_idx, visited, visited_gen, greedy_cache, input_lower = input_lower, word_mask = word_mask)
                for c_pc, c_regs in closure0:
                    expanded_batch += [(c_pc, c_regs, char_idx)]

        if not expanded_batch and anchored:
            break

        next_threads = []
        batch_match = None
        matched_priority_index = -1

        if expanded_batch:
            next_threads, batch_match, matched_priority_index = _process_batch(
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
                # For same start, matches are discovered in priority order.
                # If matched_priority_index is 0, it means it's the absolute best match
                # for this start position.
                best_match_regs = new_regs
                if matched_priority_index == 0:
                    # Early termination: No character step can ever improve this match.
                    return best_match_regs

        current_threads = next_threads

    return best_match_regs

# buildifier: disable=list-append
def parse_replacement_template(repl, named_groups = {}):
    """Parses a replacement string into a template of tokens.

    Args:
      repl: Replacement string.
      named_groups: Map of group names to IDs.

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
        if c == "\\" and i + 1 < repl_len:
            next_c = repl[i + 1]
            gid = -1

            if next_c >= "0" and next_c <= "9":
                gid = int(next_c)
                skip = 1
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
                    skip = end_name - i

            if gid != -1:
                # Flush literal buffer
                if current_literal:
                    tokens += ["".join(current_literal)]
                    current_literal = []
                tokens += [gid]
                continue

        current_literal += [c]

    if current_literal:
        tokens += ["".join(current_literal)]

    return tokens

# buildifier: disable=list-append
def expand_template(template, match_str, groups):
    """Expands a parsed replacement template.

    Args:
      template: List of tokens (strings or ints).
      match_str: The full matched string.
      groups: Tuple of captured groups.

    Returns:
      The expanded replacement string.
    """
    res = []
    for token in template:
        if type(token) == _STRING_TYPE:
            res += [token]
        else:
            gid = token
            if gid == 0:
                res += [match_str]
            elif gid <= len(groups):
                val = groups[gid - 1]
                if val != None:
                    res += [val]

    return "".join(res)

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
    template = parse_replacement_template(repl, named_groups)
    return expand_template(template, match_str, groups)

def search_regs(bytecode, text, group_count, start_index = 0, end_index = None, has_case_insensitive = False, opt = None, input_lower = None, word_mask = None):
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
      word_mask: Pre-calculated word character mask.

    Returns:
      List of registers (start/end indices) or None.
    """
    if input_lower == None and has_case_insensitive:
        input_lower = text.lower()

    effective_len = len(text) if end_index == None else end_index

    # Fast path optimization
    if opt:
        if opt.is_anchored_start:
            # If anchored at start, search is just match
            return match_regs(bytecode, text, group_count, start_index = start_index, end_index = end_index, has_case_insensitive = has_case_insensitive, opt = opt, input_lower = input_lower, word_mask = word_mask)

        if opt.is_anchored_end and not has_case_insensitive:
            # Case: ...sets...suffix$
            if text.startswith(opt.suffix, effective_len - len(opt.suffix)):
                # Work backwards from the suffix
                before_suffix_idx = effective_len - len(opt.suffix)

                # Use rstrip to find where the greedy set starts
                greedy_start = before_suffix_idx
                if opt.greedy_set_chars != None:
                    match_len = _windowed_rstrip(text, opt.greedy_set_chars, before_suffix_idx)
                    greedy_start = before_suffix_idx - match_len

                # else: no greedy_set_chars

                match_start = greedy_start
                prefix_ok = True

                # Check prefix literal
                if prefix_ok:
                    if text[:match_start].endswith(opt.prefix):
                        match_start -= len(opt.prefix)

                        regs = [-1] * ((group_count + 1) * 2 + 1)
                        regs[0] = match_start
                        regs[1] = effective_len
                        return regs

        # General case search optimization: skipping to prefix or suffix
        if opt.prefix != "":
            start_off = start_index
            search_text = text
            search_prefix = opt.prefix
            if opt.case_insensitive_prefix:
                search_text = input_lower
                search_prefix = opt.prefix.lower()

            # We can use find() to skip to the first potential match
            for _ in range(len(text)):  # Loop for find() calls
                found_idx = search_text.find(search_prefix, start_off)
                if found_idx == -1:
                    break

                # For unanchored search with prefix literal, simple skip:
                regs = match_regs(bytecode, text, group_count, start_index = found_idx, end_index = end_index, has_case_insensitive = has_case_insensitive, opt = None, input_lower = input_lower, word_mask = word_mask)
                if regs:
                    return regs

                # If match failed at found_idx, skip it and look for next prefix
                start_off = found_idx + 1
                if start_off > effective_len:
                    break
        elif opt.suffix != "":
            # Prepare search parameters
            search_text = text
            search_suffix = opt.suffix

            if opt.is_suffix_case_insensitive:
                # To handle CI search properly, we use pre-computed input_lower
                search_text = input_lower
                search_suffix = opt.suffix.lower()

            start_off = start_index
            for _ in range(len(text)):
                found_idx = search_text.find(search_suffix, start_off)
                if found_idx == -1:
                    break

                # The leftmost match must start after start_index.
                search_start = found_idx
                if opt.greedy_set_chars != None:
                    # If the greedy loop is case-insensitive, we must strip case-insensitively.
                    if opt.is_greedy_case_insensitive:
                        match_len = _windowed_rstrip(input_lower, opt.greedy_set_chars, found_idx)
                        search_start = start_index + max(0, (found_idx - match_len) - start_index)
                    else:
                        match_len = _windowed_rstrip(text, opt.greedy_set_chars, found_idx)
                        search_start = start_index + max(0, (found_idx - match_len) - start_index)

                if opt.prefix_set_chars != None:
                    if search_start > start_index and text[search_start - 1] in opt.prefix_set_chars:
                        search_start -= 1

                # Now try a real search starting at search_start
                can_bypass = False
                if opt.prefix == "" and opt.prefix_set_chars == None:
                    if opt.is_suffix_disjoint:
                        can_bypass = True
                    elif opt.is_ungreedy_loop:
                        if opt.is_greedy_case_insensitive:
                            strip_len = _windowed_lstrip(input_lower, opt.greedy_set_chars, search_start)
                        else:
                            strip_len = _windowed_lstrip(text, opt.greedy_set_chars, search_start)

                        if search_start + strip_len >= found_idx:
                            can_bypass = True

                if can_bypass:
                    # Optimization: We know we matched everything up to suffix
                    regs = [-1] * ((group_count + 1) * 2 + 1)
                    regs[0] = search_start
                    regs[1] = found_idx + len(opt.suffix)
                    return regs

                regs = match_regs(bytecode, text, group_count, start_index = search_start, end_index = end_index, has_case_insensitive = has_case_insensitive, opt = None, input_lower = input_lower, word_mask = word_mask)
                if regs:
                    return regs

                # If no match found yet, move past this suffix
                start_off = found_idx + 1
                if start_off > effective_len:
                    break

            return None

    num_regs = (group_count + 1) * 2
    return execute(bytecode, text, num_regs, start_index = start_index, end_index = end_index, anchored = False, has_case_insensitive = has_case_insensitive, input_lower = input_lower, word_mask = word_mask)

def match_regs(bytecode, text, group_count, start_index = 0, end_index = None, has_case_insensitive = False, opt = None, input_lower = None, word_mask = None):
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
      word_mask: Pre-calculated word character mask.

    Returns:
      List of registers (start/end indices) or None.
    """
    if input_lower == None and has_case_insensitive:
        input_lower = text.lower()

    effective_len = len(text) if end_index == None else end_index

    # Fast path optimization
    if opt:
        # Simple anchored prefix match
        check_text = text
        check_prefix = opt.prefix
        if opt.case_insensitive_prefix:
            check_text = input_lower
            check_prefix = opt.prefix.lower()

        if check_text.startswith(check_prefix, start_index) and start_index + len(opt.prefix) <= effective_len:
            match_end = start_index + len(opt.prefix)
            fast_path_ok = True

            # 1. Match prefix_set_chars (exactly once)
            if opt.prefix_set_chars != None:
                if match_end < effective_len and text[match_end] in opt.prefix_set_chars:
                    match_end += 1
                else:
                    fast_path_ok = False

            # 2. Match greedy_set_chars and suffix
            if fast_path_ok:
                if opt.is_anchored_end:
                    # Must match suffix at the end and greedy_set in between
                    if text.startswith(opt.suffix, effective_len - len(opt.suffix)):
                        middle_start = match_end
                        middle_end = effective_len - len(opt.suffix)
                        if middle_end >= middle_start:
                            if opt.greedy_set_chars != None:
                                strip_len = _windowed_lstrip(text, opt.greedy_set_chars, middle_start)
                                if middle_start + strip_len >= middle_end:
                                    match_end = effective_len
                                else:
                                    fast_path_ok = False
                            elif middle_start == middle_end:
                                match_end = effective_len
                            else:
                                fast_path_ok = False
                        else:
                            fast_path_ok = False
                    else:
                        fast_path_ok = False
                elif opt.suffix != "":
                    # Case: ^a*b (not anchored at end)
                    # Find first occurrence of suffix after match_end
                    found_idx = text.find(opt.suffix, match_end)
                    if found_idx != -1 and found_idx + len(opt.suffix) <= effective_len:
                        # Check if everything between match_end and found_idx is in greedy_set
                        if opt.greedy_set_chars != None:
                            strip_len = _windowed_lstrip(text, opt.greedy_set_chars, match_end)
                            if match_end + strip_len >= found_idx:
                                match_end = found_idx + len(opt.suffix)
                            else:
                                fast_path_ok = False
                        else:
                            # No greedy set, suffix must follow prefix immediately
                            if match_end == found_idx:
                                match_end = found_idx + len(opt.suffix)
                            else:
                                fast_path_ok = False
                    else:
                        fast_path_ok = False
                else:
                    # No suffix, not anchored at end
                    if opt.greedy_set_chars != None:
                        # Greedy match the rest.
                        match_len = _windowed_lstrip(text[:effective_len], opt.greedy_set_chars, match_end)
                        match_end += match_len
                    else:
                        # No greedy set, just prefix(+set)
                        pass

            if fast_path_ok:
                regs = [-1] * ((group_count + 1) * 2 + 1)
                regs[0] = start_index
                regs[1] = match_end
                return regs

    num_regs = (group_count + 1) * 2
    return execute(bytecode, text, num_regs, start_index = start_index, end_index = end_index, anchored = True, has_case_insensitive = has_case_insensitive, input_lower = input_lower, word_mask = word_mask)

def fullmatch_regs(bytecode, text, group_count, start_index = 0, end_index = None, has_case_insensitive = False, opt = None, input_lower = None, word_mask = None):
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
      word_mask: Pre-calculated word character mask.

    Returns:
      List of registers (start/end indices) or None.
    """
    if input_lower == None and has_case_insensitive:
        input_lower = text.lower()

    effective_len = len(text) if end_index == None else end_index

    # Fast path optimization
    if opt:
        # fullmatch() MUST match the entire string from start_index.
        # So it behaves like it has an implicit $ anchor.
        check_text = text
        check_prefix = opt.prefix
        check_suffix = opt.suffix
        if opt.case_insensitive_prefix:
            check_text = input_lower
            check_prefix = opt.prefix.lower()
            check_suffix = opt.suffix.lower()

        if effective_len >= len(opt.suffix) and check_text.startswith(check_prefix, start_index) and check_text.startswith(check_suffix, effective_len - len(opt.suffix)):
            match_end = start_index + len(opt.prefix)
            if match_end > effective_len - len(opt.suffix):
                fast_path_ok = False
            else:
                fast_path_ok = True

            if opt.prefix_set_chars != None:
                if match_end < effective_len and check_text[match_end] in opt.prefix_set_chars:
                    match_end += 1
                else:
                    fast_path_ok = False

            if fast_path_ok:
                middle_start = match_end
                middle_end = effective_len - len(opt.suffix)
                if middle_end >= middle_start:
                    if opt.greedy_set_chars != None:
                        strip_len = _windowed_lstrip(check_text, opt.greedy_set_chars, middle_start)
                        if middle_start + strip_len >= middle_end:
                            match_end = effective_len
                        else:
                            fast_path_ok = False
                    elif middle_start == middle_end:
                        match_end = effective_len
                    else:
                        fast_path_ok = False
                else:
                    fast_path_ok = False

            if fast_path_ok and match_end == effective_len:
                regs = [-1] * ((group_count + 1) * 2 + 1)
                regs[0] = start_index
                regs[1] = match_end
                return regs

    num_regs = (group_count + 1) * 2
    regs = execute(bytecode, text, num_regs, start_index = start_index, end_index = end_index, anchored = True, has_case_insensitive = has_case_insensitive, input_lower = input_lower, word_mask = word_mask)
    if regs and regs[1] != effective_len:
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

def search_bytecode(bytecode, text, named_groups, group_count, start_index = 0, end_index = None, has_case_insensitive = False, opt = None, input_lower = None, word_mask = None):
    """Executes a search using bytecode.

    Args:
      bytecode: The bytecode.
      text: The text.
      named_groups: Named groups map.
      group_count: Number of groups.
      start_index: Start index.
      end_index: End index (optional).
      has_case_insensitive: CI flag.
      opt: Optimization data.
      input_lower: Pre-calculated lowercase input string.
      word_mask: Pre-calculated word character mask.

    Returns:
      A MatchObject or None.
    """
    regs = search_regs(bytecode, text, group_count, start_index = start_index, end_index = end_index, has_case_insensitive = has_case_insensitive, opt = opt, input_lower = input_lower, word_mask = word_mask)
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
    effective_endpos = len(text) if end_index == None else end_index
    return MatchObject(text, regs, compiled, start_index, effective_endpos)

def match_bytecode(bytecode, text, named_groups, group_count, start_index = 0, end_index = None, has_case_insensitive = False, opt = None, input_lower = None, word_mask = None):
    """Executes a match using bytecode.

    Args:
      bytecode: The bytecode.
      text: The text.
      named_groups: Named groups map.
      group_count: Number of groups.
      start_index: Start index.
      end_index: End index (optional).
      has_case_insensitive: CI flag.
      opt: Optimization data.
      input_lower: Pre-calculated lowercase input string.
      word_mask: Pre-calculated word character mask.

    Returns:
      A MatchObject or None.
    """
    regs = match_regs(bytecode, text, group_count, start_index = start_index, end_index = end_index, has_case_insensitive = has_case_insensitive, opt = opt, input_lower = input_lower, word_mask = word_mask)
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
    effective_endpos = len(text) if end_index == None else end_index
    return MatchObject(text, regs, compiled, start_index, effective_endpos)

def fullmatch_bytecode(bytecode, text, named_groups, group_count, start_index = 0, end_index = None, has_case_insensitive = False, opt = None, input_lower = None, word_mask = None):
    """Executes a full match using bytecode.

    Args:
      bytecode: The bytecode.
      text: The text.
      named_groups: Named groups map.
      group_count: Number of groups.
      start_index: Start index.
      end_index: End index (optional).
      has_case_insensitive: CI flag.
      opt: Optimization data.
      input_lower: Pre-calculated lowercase input string.
      word_mask: Pre-calculated word character mask.

    Returns:
      A MatchObject or None.
    """
    regs = fullmatch_regs(bytecode, text, group_count, start_index = start_index, end_index = end_index, has_case_insensitive = has_case_insensitive, opt = opt, input_lower = input_lower, word_mask = word_mask)
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
    effective_endpos = len(text) if end_index == None else end_index
    return MatchObject(text, regs, compiled, start_index, effective_endpos)
