"""
A simple Regex Engine implemented in Starlark.
Supports: Literals, ., *, +, ?, |, (), [], ^, $.
Extended Support: Non-capturing groups (?:...), Shortcuts \\d, \\w, \\s.
Repetition: {n}, {n,}, {n,m}.
Quantifiers: Greedy (*, +) and Lazy (*?, +?).
Named Groups: (?P<name>...).
Boundaries: \\b, \\B.
Flags: (?i) Case Insensitive, (?m) Multiline, (?s) Dot-All.
Edge Cases: Negated sets [^abc], escaped characters in sets, and literal escaping.
Designed for environments without 're' module, recursion, or 'while' loops.
"""

MAX_GROUP_NAME_LEN = 32
MAX_EPSILON_VISITS_FACTOR = 20

# Bytecode Instructions
OP_CHAR = 0  # Match specific character
OP_ANY = 1  # Match any character (including \n)
OP_SPLIT = 2  # Jump to pc1 or pc2
OP_JUMP = 3  # Jump to pc
OP_SAVE = 4  # Save current index
OP_MATCH = 5  # Success
OP_SET = 6  # Match any in set
OP_ANCHOR_START = 7  # Match absolute start
OP_ANCHOR_END = 8  # Match absolute end
OP_WORD_BOUNDARY = 9  # Match if word/non-word transition
OP_NOT_WORD_BOUNDARY = 10  # Match if no word/non-word transition
OP_ANY_NO_NL = 11  # Match any character EXCEPT \n
OP_ANCHOR_LINE_START = 12  # Match start or after \n
OP_ANCHOR_LINE_END = 13  # Match end or before \n

def _is_word_char(c):
    """Returns True if c is [a-zA-Z0-9_]."""
    if c == None:
        return False
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"

def _get_predefined_class(char):
    """Returns (set_definition, is_negated) for \\d, \\w, \\s, \\D, \\W, \\S."""
    if char == "d":
        return ([("0", "9")], False)
    elif char == "D":
        return ([("0", "9")], True)
    elif char == "w":
        return ([("a", "z"), ("A", "Z"), ("0", "9"), "_"], False)
    elif char == "W":
        return ([("a", "z"), ("A", "Z"), ("0", "9"), "_"], True)
    elif char == "s":
        return ([" ", "\t", "\n", "\r", "\f", "\v"], False)
    elif char == "S":
        return ([" ", "\t", "\n", "\r", "\f", "\v"], True)
    return None

def _get_case_variants(char):
    """Returns list of [lower, upper] if applicable, else [char]."""
    if char >= "a" and char <= "z":
        upper = char.upper()
        return [char, upper]
    if char >= "A" and char <= "Z":
        lower = char.lower()
        return [lower, char]
    return [char]

def _compile_regex(pattern, start_group_id = 0):
    """Compiles regex to bytecode using Thompson NFA construction.

    Returns (instructions, named_groups_map, next_group_id).
    """
    instructions = []
    group_count = start_group_id
    named_groups = {}  # Map name -> gid
    i = 0
    stack = []

    # Flags state
    case_insensitive = False
    multiline = False
    dot_all = False

    # Always save group 0 (full match) start
    instructions.append((OP_SAVE, 0, None, None))

    pattern_len = len(pattern)

    # Starlark for loop to simulate while loop
    for _ in range(pattern_len * 3):
        if i >= pattern_len:
            break

        char = pattern[i]

        if char == "^":
            if multiline:
                instructions.append((OP_ANCHOR_LINE_START, None, None, None))
            else:
                instructions.append((OP_ANCHOR_START, None, None, None))

        elif char == "$":
            if multiline:
                instructions.append((OP_ANCHOR_LINE_END, None, None, None))
            else:
                instructions.append((OP_ANCHOR_END, None, None, None))

        elif char == "[":
            i += 1
            is_negated = False
            if i < pattern_len and pattern[i] == "^":
                is_negated = True
                i += 1

            char_set = []
            for _ in range(pattern_len):
                if i >= pattern_len or pattern[i] == "]":
                    break

                # Handle escaping and shortcuts inside []
                current = pattern[i]
                if current == "\\" and i + 1 < pattern_len:
                    i += 1
                    next_c = pattern[i]
                    predef = _get_predefined_class(next_c)
                    if predef:
                        pset, pneg = predef
                        if not pneg:
                            char_set.extend(pset)
                    else:
                        # Handle standard escapes inside []
                        if next_c == "n":
                            char_set.append("\n")
                        elif next_c == "r":
                            char_set.append("\r")
                        elif next_c == "t":
                            char_set.append("\t")
                        elif next_c == "f":
                            char_set.append("\f")
                        elif next_c == "v":
                            char_set.append("\v")
                        elif next_c == "x" and i + 2 < pattern_len:
                            hex_str = pattern[i + 1:i + 3]
                            valid_hex = True
                            for k in range(len(hex_str)):
                                hc = hex_str[k]
                                if not ((hc >= "0" and hc <= "9") or (hc >= "a" and hc <= "f") or (hc >= "A" and hc <= "F")):
                                    valid_hex = False
                                    break

                            if valid_hex:
                                char_set.append(chr(int(hex_str, 16)))
                                i += 2
                            else:
                                char_set.append("x")  # Fallback
                        elif case_insensitive:
                            char_set.extend(_get_case_variants(next_c))
                        else:
                            char_set.append(next_c)
                    i += 1
                    continue

                # Check for range [a-z]
                if i + 2 < pattern_len and pattern[i + 1] == "-" and pattern[i + 2] != "]":
                    start_c = pattern[i]
                    end_c = pattern[i + 2]

                    char_set.append((start_c, end_c))

                    if case_insensitive:
                        if start_c >= "a" and start_c <= "z" and end_c >= "a" and end_c <= "z":
                            char_set.append((start_c.upper(), end_c.upper()))
                        elif start_c >= "A" and start_c <= "Z" and end_c >= "A" and end_c <= "Z":
                            char_set.append((start_c.lower(), end_c.lower()))

                    i += 3
                else:
                    if case_insensitive:
                        char_set.extend(_get_case_variants(pattern[i]))
                    else:
                        char_set.append(pattern[i])
                    i += 1

            instructions.append((OP_SET, (char_set, is_negated), None, None))
            i = _handle_quantifier(pattern, i, instructions)

        elif char == "(":
            # Check for non-capturing (?:), named (?P<name>), or flags (?i, ?m, ?s)
            is_capturing = True
            group_name = None
            is_group_start = True

            if i + 2 < pattern_len and pattern[i + 1] == "?":
                la = pattern[i + 2]
                if la == ":":
                    is_capturing = False
                    i += 2
                elif la == "=" or la == "!":
                    fail("Lookarounds not supported")
                elif la == "<":
                    fail("Lookbehinds not supported")

                elif la == "P" and i + 3 < pattern_len:
                    if pattern[i + 3] == "<":
                        # Named Group (?P<name>...)
                        start_name = i + 4
                        end_name = -1
                        for k in range(start_name, min(start_name + MAX_GROUP_NAME_LEN, pattern_len)):
                            if pattern[k] == ">":
                                end_name = k
                                break
                        if end_name != -1:
                            group_name = pattern[start_name:end_name]
                            i = end_name  # Skip past >
                    elif pattern[i + 3] == "=":
                        fail("Named backreferences not supported")
                else:
                    # Check for flags e.g. (?i), (?ms), (?-s)
                    # We check looking forward
                    temp_negate = False
                    temp_case = case_insensitive
                    temp_multi = multiline
                    temp_dot = dot_all

                    k = i + 2
                    found_end = False
                    for _ in range(10):
                        if k >= pattern_len:
                            break
                        c_flag = pattern[k]
                        if c_flag == ")":
                            found_end = True
                            break
                        if c_flag == "-":
                            temp_negate = True
                        elif c_flag == "i":
                            temp_case = not temp_negate
                        elif c_flag == "m":
                            temp_multi = not temp_negate
                        elif c_flag == "s":
                            temp_dot = not temp_negate
                        else:
                            # Not a flag group, treat as normal group starting with ?
                            break
                        k += 1

                    if found_end:
                        case_insensitive = temp_case
                        multiline = temp_multi
                        dot_all = temp_dot
                        i = k  # Move to )
                        is_group_start = False

            if is_group_start:
                gid = -1
                if is_capturing:
                    group_count += 1
                    gid = group_count
                    instructions.append((OP_SAVE, gid * 2, None, None))
                    if group_name:
                        named_groups[group_name] = gid

                stack.append({
                    "type": "group",
                    "gid": gid,
                    "is_capturing": is_capturing,
                    "start_pc": len(instructions) - 1,
                    "branch_starts": [len(instructions)],
                    "exit_jumps": [],
                })

        elif char == ")":
            if stack:
                top = stack.pop()
                if top["type"] == "group":
                    if len(top["branch_starts"]) > 1:
                        top["exit_jumps"].append(len(instructions))
                        instructions.append((OP_JUMP, None, -1, None))
                        _build_alt_tree(instructions, top)

                    for jump_idx in top["exit_jumps"]:
                        instructions[jump_idx] = (OP_JUMP, None, len(instructions), None)

                    # Only emit SAVE if it was a capturing group
                    if top["is_capturing"]:
                        instructions.append((OP_SAVE, top["gid"] * 2 + 1, None, None))

                    start_pc_fix = top["start_pc"]
                    i = _handle_quantifier(pattern, i, instructions, atom_start = start_pc_fix)

        elif char == "|":
            if stack and stack[-1]["type"] == "group":
                group_ctx = stack[-1]
                group_ctx["exit_jumps"].append(len(instructions))
                instructions.append((3, None, -1, None))
                group_ctx["branch_starts"].append(len(instructions))
            else:
                instructions.append((OP_CHAR, char, None, None))

        elif char == ".":
            if dot_all:
                instructions.append((OP_ANY, None, None, None))  # ANY (includes \n)
            else:
                instructions.append((OP_ANY_NO_NL, None, None, None))  # ANY_NO_NL (excludes \n)
            i = _handle_quantifier(pattern, i, instructions)

        elif char == "\\":
            i += 1
            if i < pattern_len:
                next_c = pattern[i]

                # Check for shortcuts \d, \w, \s, \b, \B
                predef = _get_predefined_class(next_c)
                if predef:
                    # predef is (list, is_negated)
                    instructions.append((OP_SET, predef, None, None))
                elif next_c == "b":
                    instructions.append((OP_WORD_BOUNDARY, None, None, None))
                elif next_c == "B":
                    instructions.append((OP_NOT_WORD_BOUNDARY, None, None, None))
                elif next_c >= "1" and next_c <= "9":
                    fail("Backreferences not supported")
                else:
                    # Handle standard escapes
                    literal_char = None
                    if next_c == "n":
                        literal_char = "\n"
                    elif next_c == "r":
                        literal_char = "\r"
                    elif next_c == "t":
                        literal_char = "\t"
                    elif next_c == "f":
                        literal_char = "\f"
                    elif next_c == "v":
                        literal_char = "\v"
                    elif next_c == "x" and i + 2 < pattern_len:
                        hex_str = pattern[i + 1:i + 3]

                        # Starlark has no try/except. Manual check.
                        valid_hex = True
                        for k in range(len(hex_str)):
                            hc = hex_str[k]
                            if not ((hc >= "0" and hc <= "9") or (hc >= "a" and hc <= "f") or (hc >= "A" and hc <= "F")):
                                valid_hex = False
                                break

                        if valid_hex:
                            literal_char = chr(int(hex_str, 16))
                            i += 2
                        else:
                            literal_char = "x"  # Fallback

                    if literal_char:
                        instructions.append((OP_CHAR, literal_char, None, None))
                    elif case_insensitive:
                        variants = _get_case_variants(next_c)
                        if len(variants) > 1:
                            instructions.append((OP_SET, (variants, False), None, None))
                        else:
                            instructions.append((OP_CHAR, next_c, None, None))
                    else:
                        instructions.append((OP_CHAR, next_c, None, None))
                i = _handle_quantifier(pattern, i, instructions)

        else:
            if case_insensitive:
                variants = _get_case_variants(char)
                if len(variants) > 1:
                    instructions.append((6, (variants, False), None, None))
                else:
                    instructions.append((OP_CHAR, char, None, None))
            else:
                instructions.append((OP_CHAR, char, None, None))
            i = _handle_quantifier(pattern, i, instructions)

        i += 1

    # Save group 0 end and match
    instructions.append((OP_SAVE, 1, None, None))
    instructions.append((OP_MATCH, None, None, None))

    return instructions, named_groups, group_count

def _build_alt_tree(instructions, group_ctx):
    branches = group_ctx["branch_starts"]
    entry_pc = branches[0]
    orig_inst = instructions[entry_pc]
    relocated_pc = len(instructions)
    instructions.append(orig_inst)
    instructions.append((OP_JUMP, None, entry_pc + 1, None))

    tree_start_pc = len(instructions)
    current_branches = list(branches)
    current_branches[0] = relocated_pc

    for j in range(len(current_branches) - 1):
        if j < len(current_branches) - 2:
            next_split = len(instructions) + 1
            instructions.append((OP_SPLIT, None, current_branches[j], next_split))
        else:
            instructions.append((OP_SPLIT, None, current_branches[j], current_branches[-1]))

    instructions[entry_pc] = (OP_JUMP, None, tree_start_pc, None)

def _copy_insts(insts, atom_start, new_start):
    """Copies instructions from atom_start to end, shifting jumps."""
    delta = new_start - atom_start
    template = insts[atom_start:]
    new_block = []

    for op in template:
        code, val, pc1, pc2 = op

        # Shift jumps if they point inside the atom or to the immediate end
        if pc1 != None and pc1 >= atom_start:
            pc1 += delta
        if pc2 != None and pc2 >= atom_start:
            pc2 += delta
        new_block.append((code, val, pc1, pc2))

    return new_block

def _apply_question_mark(insts, atom_start, lazy = False):
    """Applies ? logic. Lazy=True tries skipping first."""
    jump_to_end_idx = len(insts)
    insts.append((OP_JUMP, None, -1, None))
    orig_first = insts[atom_start]
    reloc_idx = len(insts)
    insts.append(orig_first)
    if atom_start + 1 < jump_to_end_idx:
        insts.append((OP_JUMP, None, atom_start + 1, None))
    skip_target = len(insts)

    # Greedy: Try reloc (match) then skip. Lazy: Try skip then reloc.
    if lazy:
        insts[atom_start] = (OP_SPLIT, None, skip_target, reloc_idx)
    else:
        insts[atom_start] = (OP_SPLIT, None, reloc_idx, skip_target)
    insts[jump_to_end_idx] = (OP_JUMP, None, skip_target, None)

def _apply_star(insts, atom_start, lazy = False):
    """Applies * logic. Lazy=True tries skipping first."""
    orig_first = insts[atom_start]
    reloc_idx = len(insts)
    insts.append(orig_first)
    if len(insts) - 1 > atom_start + 1:
        insts.append((3, None, atom_start + 1, None))
    insts.append((OP_JUMP, None, atom_start, None))
    skip_target = len(insts)

    # Greedy: Try reloc (loop) then skip. Lazy: Try skip then reloc.
    if lazy:
        insts[atom_start] = (OP_SPLIT, None, skip_target, reloc_idx)
    else:
        insts[atom_start] = (OP_SPLIT, None, reloc_idx, skip_target)

def _apply_plus(insts, atom_start, lazy = False):
    """Applies + logic. Lazy=True tries exit first."""

    # Greedy: atom -> SPLIT(atom_start, next)
    # Lazy: atom -> SPLIT(next, atom_start)
    next_pc = len(insts) + 1
    if lazy:
        insts.append((OP_SPLIT, None, next_pc, atom_start))
    else:
        insts.append((OP_SPLIT, None, atom_start, next_pc))

def _handle_quantifier(pattern, i, insts, atom_start = -1):
    if atom_start == -1:
        atom_start = len(insts) - 1

    if i + 1 >= len(pattern):
        return i
    next_char = pattern[i + 1]

    # Helper to peek for lazy '?'
    # Returns (is_lazy, new_i)
    def check_lazy(idx):
        if idx + 1 < len(pattern) and pattern[idx + 1] == "?":
            return True, idx + 1
        return False, idx

    # 1. Repetition Ranges {n}, {n,}, {n,m}
    if next_char == "{":
        end_brace = -1
        for k in range(i + 2, min(i + 20, len(pattern))):
            if pattern[k] == "}":
                end_brace = k
                break

        if end_brace != -1:
            content = pattern[i + 2:end_brace]
            min_rep = 0
            max_rep = -1
            valid = True

            if "," in content:
                parts = content.split(",")
                if len(parts) == 2:
                    p0 = parts[0].strip()
                    p1 = parts[1].strip()
                    if p0 and p0.isdigit():
                        min_rep = int(p0)
                    elif p0:
                        valid = False

                    if p1 and p1.isdigit():
                        max_rep = int(p1)
                    elif p1:
                        valid = False
                else:
                    valid = False
            elif content.isdigit():
                min_rep = int(content)
                max_rep = min_rep
            else:
                valid = False

            if valid:
                is_lazy, final_i = check_lazy(end_brace)

                template = insts[atom_start:]
                for _ in range(len(template)):
                    insts.pop()

                # Expand Min
                for _ in range(min_rep):
                    _copy_insts(template, 0, len(insts))
                    curr_start = len(insts)
                    delta = curr_start - atom_start
                    for op in template:
                        code, val, pc1, pc2 = op
                        if pc1 != None and pc1 >= atom_start:
                            pc1 += delta
                        if pc2 != None and pc2 >= atom_start:
                            pc2 += delta
                        insts.append((code, val, pc1, pc2))

                # Expand Max
                if max_rep == -1:
                    block_start = len(insts)
                    delta = block_start - atom_start
                    for op in template:
                        code, val, pc1, pc2 = op
                        if pc1 != None and pc1 >= atom_start:
                            pc1 += delta
                        if pc2 != None and pc2 >= atom_start:
                            pc2 += delta
                        insts.append((code, val, pc1, pc2))
                    _apply_star(insts, block_start, lazy = is_lazy)

                elif max_rep > min_rep:
                    for _ in range(max_rep - min_rep):
                        block_start = len(insts)
                        delta = block_start - atom_start
                        for op in template:
                            code, val, pc1, pc2 = op
                            if pc1 != None and pc1 >= atom_start:
                                pc1 += delta
                            if pc2 != None and pc2 >= atom_start:
                                pc2 += delta
                            insts.append((code, val, pc1, pc2))
                        _apply_question_mark(insts, block_start, lazy = is_lazy)

                return final_i

    # 2. Standard Quantifiers
    if next_char == "?":
        is_lazy, final_i = check_lazy(i + 1)
        _apply_question_mark(insts, atom_start, lazy = is_lazy)
        return final_i
    elif next_char == "*":
        is_lazy, final_i = check_lazy(i + 1)
        _apply_star(insts, atom_start, lazy = is_lazy)
        return final_i
    elif next_char == "+":
        is_lazy, final_i = check_lazy(i + 1)
        _apply_plus(insts, atom_start, lazy = is_lazy)
        return final_i
    else:
        return i

def _get_epsilon_closure(instructions, input_str, input_len, start_pc, start_regs, current_idx):
    reachable = []
    stack = [(start_pc, start_regs)]
    visited = {}

    # Heuristic limit for epsilon closure. Starlark requires bounded loops.
    # This factor allows for complex closures (visiting instructions multiple times
    # with different registers) while preventing pathological cases from exceeding
    # O(M) work per character.
    limit = len(instructions) * MAX_EPSILON_VISITS_FACTOR

    for _ in range(limit):
        if not stack:
            break
        pc, regs = stack.pop()
        if pc >= len(instructions) or pc < 0:
            continue

        state_key = "%d_%s" % (pc, ",".join([str(x) for x in regs]))
        if state_key in visited:
            continue
        visited[state_key] = True

        inst = instructions[pc]
        itype = inst[0]

        if itype == OP_SPLIT:
            stack.append((inst[3], list(regs)))
            stack.append((inst[2], list(regs)))
        elif itype == OP_JUMP:
            stack.append((inst[2], list(regs)))
        elif itype == OP_SAVE:
            new_regs = list(regs)
            new_regs[inst[1]] = current_idx
            stack.append((pc + 1, new_regs))
        elif itype == OP_ANCHOR_START:
            if current_idx == 0:
                stack.append((pc + 1, list(regs)))
        elif itype == OP_ANCHOR_END:
            if current_idx == input_len:
                stack.append((pc + 1, list(regs)))
        elif itype == OP_WORD_BOUNDARY:
            is_prev_word = False
            if current_idx > 0:
                is_prev_word = _is_word_char(input_str[current_idx - 1])
            is_curr_word = False
            if current_idx < input_len:
                is_curr_word = _is_word_char(input_str[current_idx])
            if is_prev_word != is_curr_word:
                stack.append((pc + 1, list(regs)))
        elif itype == OP_NOT_WORD_BOUNDARY:
            is_prev_word = False
            if current_idx > 0:
                is_prev_word = _is_word_char(input_str[current_idx - 1])
            is_curr_word = False
            if current_idx < input_len:
                is_curr_word = _is_word_char(input_str[current_idx])
            if is_prev_word == is_curr_word:
                stack.append((pc + 1, list(regs)))
        elif itype == OP_ANCHOR_LINE_START:
            matched = False
            if current_idx == 0:
                matched = True
            elif current_idx > 0 and input_str[current_idx - 1] == "\n":
                matched = True
            if matched:
                stack.append((pc + 1, list(regs)))
        elif itype == OP_ANCHOR_LINE_END:
            matched = False
            if current_idx == input_len:
                matched = True
            elif current_idx < input_len and input_str[current_idx] == "\n":
                matched = True
            if matched:
                stack.append((pc + 1, list(regs)))
        else:
            reachable.append((pc, regs))

    return reachable

def _check_simple_match(inst, char):
    itype = inst[0]
    if itype == OP_CHAR:
        return inst[1] == char
    elif itype == OP_ANY:
        return True
    elif itype == OP_ANY_NO_NL:
        return char != "\n"
    elif itype == OP_SET:
        char_set_data, is_negated = inst[1]
        in_set = False
        for item in char_set_data:
            if type(item) == "tuple":
                if char >= item[0] and char <= item[1]:
                    in_set = True
                    break
            elif char == item:
                in_set = True
                break
        return (in_set != is_negated)
    return False

def _process_batch(instructions, batch, char, char_idx, input_str, input_len):
    next_threads = []
    match_regs = None

    for pc, regs in batch:
        inst = instructions[pc]
        itype = inst[0]

        if itype == OP_MATCH:
            if match_regs == None:
                match_regs = regs
            break

        if char == None:
            continue

        match_found = False
        if itype in [OP_CHAR, OP_ANY, OP_ANY_NO_NL, OP_SET]:
            match_found = _check_simple_match(inst, char)

        if match_found:
            closure = _get_epsilon_closure(instructions, input_str, input_len, pc + 1, regs, char_idx + 1)
            for c_pc, c_regs in closure:
                next_threads.append((c_pc, c_regs))
    return next_threads, match_regs

def _execute_core(instructions, input_str, num_regs, start_index = 0, initial_regs = None, anchored = False):
    if initial_regs == None:
        initial_regs = [-1] * num_regs

    input_len = len(input_str)

    # Current active threads: list of (pc, regs)
    current_threads = _get_epsilon_closure(
        instructions,
        input_str,
        input_len,
        0,
        initial_regs,
        start_index,
    )

    match_regs = None

    # Main Loop: Iterate over input string
    # We go up to input_len inclusive to handle matches at the very end (like $)
    for char_idx in range(start_index, input_len + 1):
        char = input_str[char_idx] if char_idx < input_len else None

        # Unanchored Search Injection
        if not anchored and char_idx <= input_len:
            start_closure = _get_epsilon_closure(instructions, input_str, input_len, 0, initial_regs, char_idx)
            for t in start_closure:
                current_threads.append(t)

        # Process current threads against character
        next_threads, batch_match = _process_batch(
            instructions,
            current_threads,
            char,
            char_idx,
            input_str,
            input_len,
        )

        if batch_match:
            # Prefer longer matches (greedy)
            if match_regs == None:
                match_regs = batch_match
            else:
                # Standard greedy behavior: prefer longer matches (which appear later in the loop)
                match_regs = batch_match

        current_threads = next_threads

        # Optimization: If no threads left, break
        if not current_threads and match_regs:
            break

        if not current_threads and not match_regs and char_idx > input_len:
            break

    return match_regs

def _execute(instructions, input_str, num_regs, start_index = 0, initial_regs = None, anchored = False):
    return _execute_core(instructions, input_str, num_regs, start_index, initial_regs, anchored)

def _expand_replacement(repl, match_str, groups, named_groups = {}):
    """Expands backreferences in replacement string."""

    # Simple implementation: replace \1, \2, etc.
    # Starlark doesn't have re.sub inside itself, so we iterate manually.
    res = ""
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
                    res += match_str
                elif gid <= len(groups):
                    val = groups[gid - 1]
                    if val != None:
                        res += val
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
                                res += val
                    skip = end_name - i
                    continue

        res += c
    return res

def compile(pattern):
    """Compiles a regex pattern into a reusable object.

    Args:
      pattern: The regex pattern string.

    Returns:
      A dictionary containing the compiled bytecode and metadata.
    """
    bytecode, named_groups, group_count = _compile_regex(pattern)
    return {
        "bytecode": bytecode,
        "named_groups": named_groups,
        "group_count": group_count,
        "pattern": pattern,
    }

def search(pattern, text):
    """Scan through string looking for the first location where the regex pattern produces a match.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.

    Returns:
      A dictionary containing the match results (group ID/name -> matched string),
      or None if no match was found.
    """
    if type(pattern) == "string":
        bytecode, named_groups, group_count = _compile_regex(pattern)
    else:
        # Assume it's a compiled regex object (dict)
        bytecode = pattern["bytecode"]
        named_groups = pattern["named_groups"]
        group_count = pattern["group_count"]

    # Calculate number of registers needed (2 per group + 2 for whole match)
    num_regs = (group_count + 1) * 2

    regs = _execute(bytecode, text, num_regs, anchored = False)
    if not regs:
        return None
    results = {}
    for i in range(0, len(regs), 2):
        start = regs[i]
        end = regs[i + 1]
        if start != -1 and end != -1:
            results[i // 2] = text[start:end]

    for name, gid in named_groups.items():
        if gid in results:
            results[name] = results[gid]

    return results

def match(pattern, text):
    """Try to apply the pattern at the start of the string.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.

    Returns:
      A dictionary containing the match results (group ID/name -> matched string),
      or None if no match was found.
    """
    if type(pattern) == "string":
        bytecode, named_groups, group_count = _compile_regex(pattern)
    else:
        # Assume it's a compiled regex object (dict)
        bytecode = pattern["bytecode"]
        named_groups = pattern["named_groups"]
        group_count = pattern["group_count"]

    # Calculate number of registers needed (2 per group + 2 for whole match)
    num_regs = (group_count + 1) * 2

    regs = _execute(bytecode, text, num_regs, anchored = True)
    if not regs:
        return None
    results = {}
    for i in range(0, len(regs), 2):
        start = regs[i]
        end = regs[i + 1]
        if start != -1 and end != -1:
            results[i // 2] = text[start:end]

    for name, gid in named_groups.items():
        if gid in results:
            results[name] = results[gid]

    return results

def fullmatch(pattern, text):
    """Try to apply the pattern to the entire string.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.

    Returns:
      A dictionary containing the match results (group ID/name -> matched string),
      or None if no match was found.
    """
    res = match(pattern, text)
    if res and len(res[0]) == len(text):
        return res
    return None

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
    if type(pattern) == "string":
        compiled = compile(pattern)
    else:
        compiled = pattern

    bytecode = compiled["bytecode"]
    group_count = compiled["group_count"]
    num_regs = (group_count + 1) * 2

    matches = []
    start_index = 0
    text_len = len(text)

    # Starlark doesn't support while loops, so we use a large range
    # Max possible matches is len(text) + 1 (for empty matches)
    for _ in range(text_len + 2):
        regs = _execute(bytecode, text, num_regs, start_index = start_index)
        if not regs:
            break

        match_start = regs[0]
        match_end = regs[1]

        if match_start == -1:
            # Should not happen if execute returns non-None
            break

        # Extract result
        if group_count == 0:
            matches.append(text[match_start:match_end])
        else:
            # Return groups
            groups = []
            for i in range(1, group_count + 1):
                g_start = regs[i * 2]
                g_end = regs[i * 2 + 1]
                if g_start != -1 and g_end != -1:
                    groups.append(text[g_start:g_end])
                else:
                    groups.append(None)

            # Starlark doesn't have tuples in the same way, return tuple-like list or tuple
            # Using tuple() to match Python behavior closer if possible, or just list
            matches.append(tuple(groups))

        # Advance start_index
        if match_end > match_start:
            start_index = match_end
        else:
            # Empty match, advance by 1 to avoid infinite loop
            start_index = match_end + 1

        if start_index > text_len:
            break

    return matches

def _MatchObject(text, regs, compiled, pos, endpos):
    """Constructs a match object with methods.

    TODO: Convert this to a struct when migrating to Bazel rules (which support structs).
    """

    def group(n = 0):
        if n < 0 or n > compiled["group_count"]:
            fail("IndexError: no such group")
        start = regs[n * 2]
        end = regs[n * 2 + 1]
        if start == -1 or end == -1:
            return None
        return text[start:end]

    def groups(default = None):
        res = []
        for i in range(1, compiled["group_count"] + 1):
            start = regs[i * 2]
            end = regs[i * 2 + 1]
            if start == -1 or end == -1:
                res.append(default)
            else:
                res.append(text[start:end])
        return tuple(res)

    def span(n = 0):
        if n < 0 or n > compiled["group_count"]:
            fail("IndexError: no such group")
        return (regs[n * 2], regs[n * 2 + 1])

    return {
        "group": group,
        "groups": groups,
        "span": span,
        "string": text,
        "re": compiled,
        "pos": pos,
        "endpos": endpos,
        "lastindex": None,  # TODO: Track last capturing group
        "lastgroup": None,  # TODO: Track last capturing group name
    }

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
    if type(pattern) == "string":
        compiled = compile(pattern)
    else:
        compiled = pattern

    # Reuse findall logic but we need the match objects (start/end indices)
    # findall returns strings/tuples, which loses index info.
    # So we duplicate the loop here or refactor findall to return match objects.
    # Let's duplicate loop for now to avoid breaking findall API.

    bytecode = compiled["bytecode"]
    group_count = compiled["group_count"]
    num_regs = (group_count + 1) * 2

    res_parts = []
    last_idx = 0
    start_index = 0
    text_len = len(text)
    matches_found = 0

    # Simulate while loop
    for _ in range(text_len + 2):
        if count > 0 and matches_found >= count:
            break

        regs = _execute(bytecode, text, num_regs, start_index = start_index)
        if not regs:
            break

        match_start = regs[0]
        match_end = regs[1]

        if match_start == -1:
            break

        # Append text before match
        res_parts.append(text[last_idx:match_start])

        # Calculate replacement
        match_str = text[match_start:match_end]

        groups = []
        for i in range(1, group_count + 1):
            g_start = regs[i * 2]
            g_end = regs[i * 2 + 1]
            if g_start != -1 and g_end != -1:
                groups.append(text[g_start:g_end])
            else:
                groups.append(None)

        if type(repl) == "function":
            # Pass a match object (dict with methods)
            match_obj = _MatchObject(text, regs, compiled, match_start, match_end)
            replacement = repl(match_obj)
        else:
            replacement = _expand_replacement(repl, match_str, groups, compiled["named_groups"])

        res_parts.append(replacement)

        last_idx = match_end
        matches_found += 1

        # Advance start_index
        if match_end > match_start:
            start_index = match_end
        else:
            start_index = match_end + 1

        if start_index > text_len:
            break

    res_parts.append(text[last_idx:])
    return "".join(res_parts)

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

    if type(pattern) == "string":
        compiled = compile(pattern)
    else:
        compiled = pattern

    bytecode = compiled["bytecode"]
    group_count = compiled["group_count"]
    num_regs = (group_count + 1) * 2

    res_parts = []
    last_idx = 0
    start_index = 0
    text_len = len(text)
    splits = 0

    # Simulate while loop
    for _ in range(text_len + 2):
        if maxsplit > 0 and splits >= maxsplit:
            break

        regs = _execute(bytecode, text, num_regs, start_index = start_index)
        if not regs:
            break

        match_start = regs[0]
        match_end = regs[1]

        if match_start == -1:
            break

        # Append text before match
        res_parts.append(text[last_idx:match_start])

        # If capturing groups, append them too (Python behavior)
        if group_count > 0:
            for i in range(1, group_count + 1):
                g_start = regs[i * 2]
                g_end = regs[i * 2 + 1]
                if g_start != -1 and g_end != -1:
                    res_parts.append(text[g_start:g_end])
                else:
                    res_parts.append(None)

        last_idx = match_end
        splits += 1

        # Advance start_index
        if match_end > match_start:
            start_index = match_end
        else:
            start_index = match_end + 1

        if start_index > text_len:
            break

    res_parts.append(text[last_idx:])
    return res_parts
