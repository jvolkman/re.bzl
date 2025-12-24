"""Compiler for Starlark Regex Engine."""

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
    "OP_WORD_BOUNDARY",
    _CHR_LOOKUP = "CHR_LOOKUP",
    _ORD_LOOKUP = "ORD_LOOKUP",
)

# Maximum number of characters to scan forward when parsing inline regex flags (e.g., '(?i)').
# This prevents runaway scanning in malformed patterns where the closing ')' or ':' is missing.
MAX_FLAGS_LEN = 10

# Maximum number of iterations for optimization passes that collapse jump chains (e.g., JUMP -> JUMP).
# This allows flattening deep jump sequences while providing a safety break against potential
# infinite cycles that could arise from malformed bytecode during the compilation phase.
MAX_OPTIMIZATION_PASSES = 100

def _inst(op, val = None, **kwargs):
    return struct(op = op, val = val, **kwargs)

_PREDEFINED_CLASSES = {
    "d": ([("0", "9")], False),
    "D": ([("0", "9")], True),
    "w": ([("a", "z"), ("A", "Z"), ("0", "9"), ("_", "_")], False),
    "W": ([("a", "z"), ("A", "Z"), ("0", "9"), ("_", "_")], True),
    "s": ([(" ", " "), ("\t", "\t"), ("\n", "\n"), ("\r", "\r"), ("\f", "\f"), ("\v", "\v")], False),
    "S": ([(" ", " "), ("\t", "\t"), ("\n", "\n"), ("\r", "\r"), ("\f", "\f"), ("\v", "\v")], True),
}

_POSIX_CLASSES = {
    "alnum": [("0", "9"), ("A", "Z"), ("a", "z")],
    "alpha": [("A", "Z"), ("a", "z")],
    "ascii": [("\000", "\177")],
    "blank": [(" ", " "), ("\t", "\t")],
    "cntrl": [("\000", "\037"), ("\177", "\177")],
    "digit": [("0", "9")],
    "graph": [("\041", "\176")],
    "lower": [("a", "z")],
    "print": [("\040", "\176")],
    "punct": [("\041", "\057"), ("\072", "\100"), ("\133", "\140"), ("\173", "\176")],
    "space": [(" ", " "), ("\t", "\t"), ("\n", "\n"), ("\r", "\r"), ("\f", "\f"), ("\v", "\v")],
    "upper": [("A", "Z")],
    "word": [("0", "9"), ("A", "Z"), ("a", "z"), ("_", "_")],
    "xdigit": [("0", "9"), ("A", "F"), ("a", "f")],
}

_SIMPLE_ESCAPES = {
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "f": "\f",
    "v": "\v",
    "a": "\007",
}

def _get_predefined_class(char):
    """Returns (set_definition, is_negated) for \\d, \\w, \\s, \\D, \\W, \\S."""
    return _PREDEFINED_CLASSES.get(char)

def _get_posix_class(name):
    """Returns the character set for a POSIX class name."""
    return _POSIX_CLASSES.get(name)

# buildifier: disable=list-append
# buildifier: disable=list-append
def _new_set_builder(case_insensitive = False):
    """Returns a builder for creating a character set struct."""
    state = {
        "lookup": {},
        "ranges": [],
        "negated_posix_list": [],
        "all_chars_list": [],
        "ascii_list": [False] * 256,
    }

    # RANGE_EXPANSION_LIMIT defines the maximum distance between start and end codes in a
    # character range (e.g., [a-z]) that will be expanded into individual characters in
    # the 'lookup' dictionary. Expanding ranges allows for O(1) membership checks during
    # regex execution but increases memory usage. Ranges larger than this limit are
    # stored as (start, end) tuples and checked via range comparison.
    RANGE_EXPANSION_LIMIT = 512

    # ALL_CHARS_STR_LIMIT defines the maximum number of unique characters that can be
    # stored in the 'all_chars' string for a character set. If a set contains fewer
    # characters than this limit (and has no large unexpanded ranges or negated POSIX
    # classes), it is marked as 'is_simple'. Simple sets can be matched more efficiently
    # by the VM using string-in-string checks (e.g., char in all_chars_str).
    ALL_CHARS_STR_LIMIT = 2048

    def add_char(c):
        if case_insensitive:
            c = c.lower()
        state["lookup"][c] = True
        state["all_chars_list"] += [c]
        code = _ORD_LOOKUP[c]
        if code < 256:
            state["ascii_list"][code] = True

    def add_range(start, end):
        start_code = _ORD_LOOKUP[start]
        end_code = _ORD_LOOKUP[end]
        dist = end_code - start_code

        # Update ASCII list (intersection with 0-255)
        if start_code < 256:
            limit = end_code
            if limit > 255:
                limit = 255
            for k in range(start_code, limit + 1):
                c_iter = _CHR_LOOKUP[k]
                if case_insensitive:
                    c_iter = c_iter.lower()
                code_final = _ORD_LOOKUP[c_iter]
                if code_final < 256:
                    state["ascii_list"][code_final] = True

        if dist < RANGE_EXPANSION_LIMIT:
            for code in range(start_code, end_code + 1):
                c = _CHR_LOOKUP[code]
                if case_insensitive:
                    c = c.lower()
                state["lookup"][c] = True
                state["all_chars_list"] += [c]
        else:
            state["ranges"] += [(start, end)]

    def add_negated_posix(pset):
        # pset is a list of atoms (chars or ranges)
        # pset is a list of atoms (chars or ranges)
        state["negated_posix_list"] += [pset]

        # Update ASCII list
        for k in range(256):
            # Check if k is in pset
            in_pset = False
            for item in pset:
                # item is char "c" or range ("c1", "c2") - wait, pset format?
                # _PREDEFINED_CLASSES values are ([("0", "9")], False).
                # _POSIX_CLASSES values are [("0", "9"), ...].
                # So item is always a range tuple?
                # Let's check _get_posix_class returns list of tuples.
                # _compile_bracket_class calls add_negated_posix with atom.negated_atoms
                # _parse_set_atom returns negated_atoms=pset (from _get_posix_class)
                # So yes, pset is list of (start_char, end_char) tuples.

                # Check ranges
                s, e = item
                if k >= _ORD_LOOKUP[s] and k <= _ORD_LOOKUP[e]:
                    in_pset = True
                    break

            if not in_pset:
                state["ascii_list"][k] = True

    def build():
        # Deduplicate for all_chars_str
        all_chars_val = []
        seen_str = {}
        for c in state["all_chars_list"]:
            if c not in seen_str:
                seen_str[c] = True
                if len(all_chars_val) < ALL_CHARS_STR_LIMIT:
                    all_chars_val += [c]
        all_chars_str = "".join(all_chars_val)

        # Check if set is simple (fully represented by all_chars)
        is_simple = (len(state["ranges"]) == 0 and
                     len(state["negated_posix_list"]) == 0 and
                     len(all_chars_val) < ALL_CHARS_STR_LIMIT)

        return struct(
            lookup = state["lookup"],
            ranges = state["ranges"],
            negated_posix = state["negated_posix_list"],
            all_chars = all_chars_str,
            is_simple = is_simple,
            ascii_bitmap = tuple(state["ascii_list"]),
        )

    return struct(
        add_char = add_char,
        add_range = add_range,
        add_negated_posix = add_negated_posix,
        build = build,
    )

def _parse_escape(pattern, i, pattern_len):
    """Parses an escape sequence at i. Returns (char, last_consumed_i)."""
    if i >= pattern_len:
        return None, i

    char = pattern[i]

    if char == "x":
        if i + 1 < pattern_len and pattern[i + 1] == "{":
            # \x{h...h}
            end_brace = -1
            for k in range(i + 2, min(i + 12, pattern_len)):
                if pattern[k] == "}":
                    end_brace = k
                    break
            if end_brace != -1:
                hex_str = pattern[i + 2:end_brace]

                # Starlark int(s, 16) works
                val = int(hex_str, 16)
                if val <= 255:
                    return _CHR_LOOKUP[val], end_brace
                else:
                    # For now, we only support up to 255 in our _chr lookup
                    # but we could return the raw int if we changed _chr
                    fail("Hex escape too large: " + hex_str)

        if i + 2 < pattern_len:
            hex_str = pattern[i + 1:i + 3]
            valid_hex = True
            for k in range(len(hex_str)):
                hc = hex_str[k]
                if not ((hc >= "0" and hc <= "9") or (hc >= "a" and hc <= "f") or (hc >= "A" and hc <= "F")):
                    valid_hex = False
                    break

            if valid_hex:
                return _CHR_LOOKUP[int(hex_str, 16)], i + 2
        return "x", i

    if char >= "0" and char <= "7":
        oct_str = char
        consumed = 0
        if i + 1 < pattern_len and pattern[i + 1] >= "0" and pattern[i + 1] <= "7":
            oct_str += pattern[i + 1]
            consumed = 1
            if i + 2 < pattern_len and pattern[i + 2] >= "0" and pattern[i + 2] <= "7":
                # Check if <= 377 (255)
                if int(oct_str + pattern[i + 2], 8) <= 255:
                    oct_str += pattern[i + 2]
                    consumed = 2
        return _CHR_LOOKUP[int(oct_str, 8)], i + 1 + consumed

    # Look up simple escapes (\n, \r, etc.)
    if char in _SIMPLE_ESCAPES:
        return _SIMPLE_ESCAPES[char], i

    return char, i

def _parse_set_atom(pattern, i, pattern_len):
    """Parses one atom in a set.

    Returns (atom_data, new_i).
    atom_data is a struct(char=c, atoms=list, negated_atoms=list). Only one field is set.
    """
    current = pattern[i]

    if current == "\\" and i + 1 < pattern_len:
        i += 1
        next_c = pattern[i]
        predef = _get_predefined_class(next_c)
        if predef:
            pset, pneg = predef
            if not pneg:
                return struct(char = None, atoms = pset, negated_atoms = None), i + 1
            else:
                # Predefined negated classes (\D, \W, \S) are not supported inside [] blocks
                # consistent with previous implementation.
                return struct(char = None, atoms = [], negated_atoms = None), i + 1
        else:
            # Handle escapes inside []
            char, new_i = _parse_escape(pattern, i, pattern_len)

            # new_i is the last consumed index (e.g. 'n' in \n)
            # The next atom starts at new_i + 1
            return struct(char = char, atoms = None, negated_atoms = None), new_i + 1
    elif current == "[" and i + 1 < pattern_len and pattern[i + 1] == ":":
        # POSIX class [[:name:]]
        i += 2
        is_negated = False
        if i < pattern_len and pattern[i] == "^":
            is_negated = True
            i += 1

        start_name = i
        end_name = -1
        for k in range(i, pattern_len - 1):
            if pattern[k] == ":" and pattern[k + 1] == "]":
                end_name = k
                break

        if end_name != -1:
            name = pattern[start_name:end_name]
            pset = _get_posix_class(name)
            if pset:
                if is_negated:
                    return struct(char = None, atoms = None, negated_atoms = pset), end_name + 2
                else:
                    return struct(char = None, atoms = pset, negated_atoms = None), end_name + 2
            else:
                # Not a valid POSIX class, treat as literal [
                return struct(char = "[", atoms = None, negated_atoms = None), i
        else:
            # No closing :], treat as literal [
            return struct(char = "[", atoms = None, negated_atoms = None), i
    else:
        return struct(char = current, atoms = None, negated_atoms = None), i + 1

def _compile_bracket_class(pattern, i, pattern_len, case_insensitive):
    """Compiles a [...] set expression.

    Returns (set_struct, is_negated, closing_bracket_index).
    """
    is_negated = False
    if i < pattern_len and pattern[i] == "^":
        is_negated = True
        i += 1

    builder = _new_set_builder(case_insensitive = case_insensitive)
    first = True
    for _ in range(pattern_len):
        if i >= pattern_len:
            break
        if pattern[i] == "]" and not first:
            break
        first = False

        atom, new_i = _parse_set_atom(pattern, i, pattern_len)

        is_range = False
        if atom.char != None and new_i < pattern_len and pattern[new_i] == "-" and new_i + 1 < pattern_len and pattern[new_i + 1] != "]":
            end_atom, end_i = _parse_set_atom(pattern, new_i + 1, pattern_len)
            if end_atom.char != None:
                builder.add_range(atom.char, end_atom.char)
                i = end_i
                is_range = True

        if not is_range:
            if atom.char != None:
                builder.add_char(atom.char)
            elif atom.atoms != None:
                for item in atom.atoms:
                    builder.add_range(item[0], item[1])
            elif atom.negated_atoms != None:
                builder.add_negated_posix(atom.negated_atoms)
            i = new_i

    return builder.build(), is_negated, i

def _parse_group_start(pattern, i, pattern_len, flags):
    """Parses a group start '('.

    Returns struct(new_i, is_capturing, group_name, is_group_start, new_flags).
    """
    case_insensitive, multiline, dot_all, ungreedy = flags
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
            # Check if it's (?<name>...)
            if i + 3 < pattern_len and not (pattern[i + 3] == "=" or pattern[i + 3] == "!"):
                # Named Group (?<name>...)
                start_name = i + 3
                end_name = -1
                for k in range(start_name, min(start_name + MAX_GROUP_NAME_LEN, pattern_len)):
                    if pattern[k] == ">":
                        end_name = k
                        break
                if end_name != -1:
                    group_name = pattern[start_name:end_name]
                    i = end_name  # Skip past >
            else:
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
            # Check for flags e.g. (?i), (?ms), (?-s), (?i:...)
            # We check looking forward
            temp_negate = False
            temp_case = case_insensitive
            temp_multi = multiline
            temp_dot = dot_all
            temp_ungreedy = ungreedy

            k = i + 2
            found_end = False
            is_scoped = False

            # Limit scanning for flags to a reasonable length to avoid runaway parsing.
            for _ in range(MAX_FLAGS_LEN):
                if k >= pattern_len:
                    break
                c_flag = pattern[k]
                if c_flag == ")":
                    found_end = True
                    break
                if c_flag == ":":
                    found_end = True
                    is_scoped = True
                    break
                if c_flag == "-":
                    temp_negate = True
                elif c_flag == "i":
                    temp_case = not temp_negate
                elif c_flag == "m":
                    temp_multi = not temp_negate
                elif c_flag == "s":
                    temp_dot = not temp_negate
                elif c_flag == "U":
                    temp_ungreedy = not temp_negate
                else:
                    # Not a flag group, treat as normal group starting with ?
                    break
                k += 1

            if found_end:
                case_insensitive = temp_case
                multiline = temp_multi
                dot_all = temp_dot
                ungreedy = temp_ungreedy
                i = k  # Move to ) or :

                if is_scoped:
                    is_capturing = False
                    is_group_start = True
                else:
                    is_group_start = False

    return struct(
        new_i = i,
        is_capturing = is_capturing,
        group_name = group_name,
        is_group_start = is_group_start,
        new_flags = (case_insensitive, multiline, dot_all, ungreedy),
    )

def _is_disjoint(body_inst, next_inst):
    """Returns True if the body instruction is disjoint from the next instruction."""
    b_type = body_inst.op
    n_type = next_inst.op

    # 1. Body must be a simple Set or Char
    b_chars = None
    b_lookup = None
    b_is_case_insensitive = False

    if b_type == OP_CHAR:
        b_chars = body_inst.val
        b_is_case_insensitive = body_inst.is_ci
    elif b_type == OP_SET:
        # Check if set is simple
        set_struct, is_negated = body_inst.val
        b_is_case_insensitive = body_inst.is_ci
        if is_negated or not set_struct.is_simple:
            return False
        b_chars = set_struct.all_chars
        b_lookup = set_struct.lookup
    else:
        # Complex body (e.g. Group, Any) - not optimizing yet
        return False

    # 2. Check Next instruction
    if n_type == OP_MATCH:
        # End of pattern is disjoint from any char/set
        return True

    if n_type == OP_CHAR:
        n_char = next_inst.val
        n_is_ci = next_inst.is_ci

        if b_is_case_insensitive:
            # Body is lowercased.
            if n_is_ci:
                # Next is lowercased. Direct check.
                check_char = n_char
            else:
                # Next is CS. Must check lower(n_char).
                check_char = n_char.lower()

            if b_lookup:
                return check_char not in b_lookup
            else:
                return check_char != b_chars

        else:
            # Body is CS.
            if n_is_ci:
                # Next is CI (lower).
                # Conservative: Skip mixing CS body with CI next
                return False
            else:
                # Legacy CS-CS
                if b_lookup:
                    return n_char not in b_lookup
                else:
                    return n_char != b_chars

    if n_type == OP_SET:
        # Conservative: Skip if next is Set
        return False

    if n_type == OP_ANCHOR_END or n_type == OP_ANCHOR_LINE_END:
        return True

    if n_type == OP_ANCHOR_START or n_type == OP_ANCHOR_LINE_START:
        return True

    # Default unsafe
    return False

def _remap_inst(inst, old_to_new):
    """Remaps instruction PCs based on old_to_new mapping."""
    itype = inst.op
    val = inst.val

    if itype == OP_JUMP:
        target = inst.target
        if target != None and target in old_to_new:
            return _inst(OP_JUMP, val = val, target = old_to_new[target])
        return inst

    if itype == OP_SPLIT:
        pc1 = inst.pc1
        pc2 = inst.pc2
        new_pc1 = old_to_new.get(pc1, pc1)
        new_pc2 = old_to_new.get(pc2, pc2)
        if new_pc1 != pc1 or new_pc2 != pc2:
            return _inst(itype, val = val, pc1 = new_pc1, pc2 = new_pc2)
        return inst

    if itype == OP_GREEDY_LOOP:
        exit_pc = inst.exit_pc
        new_exit = old_to_new.get(exit_pc, exit_pc)
        if new_exit != exit_pc:
            return _inst(itype, val = val, exit_pc = new_exit, is_ci = inst.is_ci)
        return inst

    return inst

# buildifier: disable=list-append
def _shift_insts(insts, atom_start, new_start):
    """Copies instructions from atom_start to end, shifting jumps."""
    delta = new_start - atom_start
    template = insts[atom_start:]
    new_block = []

    for inst in template:
        itype, val = inst.op, inst.val

        if itype == OP_JUMP:
            target = inst.target
            if target != None and target >= atom_start:
                target += delta
            new_block += [_inst(OP_JUMP, val = val, target = target)]
        elif itype == OP_SPLIT:
            pc1 = inst.pc1
            pc2 = inst.pc2
            if pc1 != None and pc1 >= atom_start:
                pc1 += delta
            if pc2 != None and pc2 >= atom_start:
                pc2 += delta
            new_block += [_inst(OP_SPLIT, val = val, pc1 = pc1, pc2 = pc2)]
        elif itype == OP_GREEDY_LOOP:
            exit_pc = inst.exit_pc
            if exit_pc != None and exit_pc >= atom_start:
                exit_pc += delta
            new_block += [_inst(OP_GREEDY_LOOP, val = val, exit_pc = exit_pc, is_ci = inst.is_ci)]
        else:
            new_block += [inst]

    return new_block

# buildifier: disable=list-append
def _optimize_greedy_loops(instructions):
    """Detects and optimizes simple greedy loops [a-z]*"""
    num_insts = len(instructions)
    new_insts = []
    old_to_new = {}
    skip = 0

    for i in range(num_insts):
        if skip > 0:
            skip -= 1
            continue

        old_to_new[i] = len(new_insts)
        inst = instructions[i]

        # Pattern: Split(Body, Exit)
        if inst.op == OP_SPLIT:
            body_pc = inst.pc1
            exit_pc = inst.pc2

            # Sanity check PCs
            if body_pc > i and body_pc < num_insts and exit_pc > i and exit_pc < num_insts:
                body_inst = instructions[body_pc]

                # Pattern 1: Body -> Jump(Split) (Legacy)
                # Pattern 2: Body -> Split(Split, Exit) (New)
                # Check if body is followed by loop back to i
                loop_back_pc = body_pc + 1
                if loop_back_pc < num_insts:
                    loop_inst = instructions[loop_back_pc]
                    if (loop_inst.op == OP_JUMP and loop_inst.target == i) or \
                       (loop_inst.op == OP_SPLIT and loop_inst.pc1 == i):
                        # Pattern: Exit -> Continuation
                        exit_inst = instructions[exit_pc]

                        if _is_disjoint(body_inst, exit_inst):
                            # Optimize!
                            # Convert body to string chars
                            chars = ""
                            is_ci = False

                            if body_inst.op == OP_CHAR:
                                chars = body_inst.val
                                is_ci = body_inst.is_ci
                            elif body_inst.op == OP_SET:  # OP_SET
                                chars = body_inst.val[0].all_chars
                                is_ci = body_inst.is_ci

                            # Emit OP_GREEDY_LOOP
                            # (OP_GREEDY_LOOP, chars, exit_pc, is_ci)
                            new_insts += [_inst(OP_GREEDY_LOOP, val = chars, exit_pc = exit_pc, is_ci = is_ci)]
                            skip = 2  # Skip body and loop_back
                            continue

        new_insts += [inst]

    # Remap PCs
    # Standard remapping logic:
    for i in range(num_insts):
        if i not in old_to_new:
            # It was skipped.
            pass

    mapped_insts = []
    for inst in new_insts:
        itype = inst.op
        if itype == OP_GREEDY_LOOP:
            chars = inst.val
            old_exit = inst.exit_pc
            is_ci = inst.is_ci

            # Defer resolution to post-pass
            mapped_insts += [_inst(itype, val = chars, exit_pc = old_exit, is_ci = is_ci)]
        else:
            mapped_insts += [inst]

    # Post-pass to fix PCs
    final = []
    for inst in mapped_insts:
        final += [_remap_inst(inst, old_to_new)]

    return final

# buildifier: disable=list-append
def _optimize_strings(instructions):
    # 1. Collect jump targets to be safe
    jump_targets = {}
    for inst in instructions:
        itype = inst.op
        target = None
        target2 = None

        if itype == OP_JUMP:
            target = inst.target
        elif itype == OP_SPLIT:
            target = inst.pc1
            target2 = inst.pc2
        elif itype == OP_GREEDY_LOOP:
            target = inst.exit_pc

        if target != None:
            jump_targets[target] = True
        if target2 != None:
            jump_targets[target2] = True

    new_insts = []
    old_to_new = {}
    num_insts = len(instructions)

    skip = 0
    for i in range(num_insts):
        if skip > 0:
            skip -= 1

            # Still map skipped instructions for safety, mapping to the merged instruction
            # which is the last added instruction in new_insts
            if new_insts:
                old_to_new[i] = len(new_insts) - 1
            continue

        old_to_new[i] = len(new_insts)
        inst = instructions[i]
        itype = inst.op
        val = inst.val

        merged = False

        if itype == OP_CHAR:
            # Try to start building a string
            current_val = val
            current_is_ci = inst.is_ci

            # Look ahead
            match_end = i + 1

            for local_j in range(i + 1, num_insts):
                # Check jump targets
                if local_j in jump_targets:
                    break

                next_inst = instructions[local_j]

                # Can only merge if next is also OP_CHAR and has the same case sensitivity
                if next_inst.op == OP_CHAR and next_inst.is_ci == current_is_ci:
                    current_val += next_inst.val
                    match_end = local_j + 1
                else:
                    break

            if match_end > i + 1:
                # We merged!
                # Note: current_val is already lowercase if current_is_ci is true
                new_insts.append(_inst(OP_STRING, val = current_val, is_ci = current_is_ci))
                skip = match_end - i - 1
                merged = True

        if not merged:
            new_insts.append(inst)

    # Remap jumps
    final_insts = []
    for inst in new_insts:
        final_insts.append(_remap_inst(inst, old_to_new))

    return final_insts

# buildifier: disable=list-append
def _optimize_jumps(instructions):
    """Collapses chains of JUMP -> JUMP and SPLIT -> JUMP."""
    num_insts = len(instructions)

    # Collapsing jump chains (JUMP A -> JUMP B) can require multiple passes.
    # We use a large enough limit to catch deep chains while preventing infinite
    # loops in case of malformed bytecode cycles.
    for _ in range(MAX_OPTIMIZATION_PASSES):
        optimized = False
        old_to_new = {}
        for i in range(num_insts):
            inst = instructions[i]
            if inst.op == OP_JUMP:
                target = inst.target
                if target != None and target < num_insts:
                    next_inst = instructions[target]
                    if next_inst.op == OP_JUMP and next_inst.target != target:
                        old_to_new[target] = next_inst.target
                        optimized = True

        if not optimized:
            break

        new_insts = []
        for inst in instructions:
            new_insts.append(_remap_inst(inst, old_to_new))
        instructions = new_insts

    return instructions

def _optimize_bytecode(instructions):
    """Optimizes instructions for performance."""

    instructions = _optimize_greedy_loops(instructions)
    instructions = _optimize_strings(instructions)
    instructions = _optimize_jumps(instructions)
    return instructions

# buildifier: disable=list-append
def _build_alt_tree(instructions, group_ctx):
    branches = group_ctx["branch_starts"]
    entry_pc = branches[0]
    orig_inst = instructions[entry_pc]
    relocated_pc = len(instructions)
    instructions += [orig_inst]
    instructions += [_inst(OP_JUMP, target = entry_pc + 1)]

    tree_start_pc = len(instructions)
    current_branches = branches[:]
    current_branches[0] = relocated_pc

    for j in range(len(current_branches) - 1):
        if j < len(current_branches) - 2:
            next_split = len(instructions) + 1
            instructions += [_inst(OP_SPLIT, pc1 = current_branches[j], pc2 = next_split)]
        else:
            instructions += [_inst(OP_SPLIT, pc1 = current_branches[j], pc2 = current_branches[-1])]

    instructions[entry_pc] = _inst(OP_JUMP, target = tree_start_pc)

# buildifier: disable=list-append
def _apply_question_mark(insts, atom_start, lazy = False):
    """Applies ? logic. Lazy=True tries skipping first."""
    new_block = _shift_insts(insts, atom_start, atom_start + 1)

    # Remove original atom
    for _ in range(len(insts) - atom_start):
        insts.pop()

    split_pc = len(insts)  # atom_start
    insts += [None]  # Placeholder

    atom_pc = len(insts)
    insts += new_block

    skip_target = len(insts)

    if lazy:
        insts[split_pc] = _inst(OP_SPLIT, pc1 = skip_target, pc2 = atom_pc)
    else:
        insts[split_pc] = _inst(OP_SPLIT, pc1 = atom_pc, pc2 = skip_target)

# buildifier: disable=list-append
def _apply_star(insts, atom_start, lazy = False):
    """Applies * logic. Lazy=True tries skipping first."""
    new_block = _shift_insts(insts, atom_start, atom_start + 1)

    # Remove original atom
    for _ in range(len(insts) - atom_start):
        insts.pop()

    split_pc = len(insts)  # atom_start
    insts += [None]  # Placeholder

    atom_pc = len(insts)
    insts += new_block

    # Jump back replaced by SPLIT to allow one extra empty match for groups
    end_split_pc = len(insts)
    insts += [None]  # Placeholder
    skip_target = len(insts)

    if lazy:
        insts[end_split_pc] = _inst(OP_SPLIT, pc1 = skip_target, pc2 = split_pc)
        insts[split_pc] = _inst(OP_SPLIT, pc1 = skip_target, pc2 = atom_pc)
    else:
        insts[end_split_pc] = _inst(OP_SPLIT, pc1 = split_pc, pc2 = skip_target)
        insts[split_pc] = _inst(OP_SPLIT, pc1 = atom_pc, pc2 = skip_target)

# buildifier: disable=list-append
def _apply_plus(insts, atom_start, lazy = False):
    """Applies + logic. Lazy=True tries exit first."""

    # Greedy: atom -> SPLIT(atom_start, next)
    # Lazy: atom -> SPLIT(next, atom_start)
    next_pc = len(insts) + 1
    if lazy:
        insts += [_inst(OP_SPLIT, pc1 = next_pc, pc2 = atom_start)]
    else:
        insts += [_inst(OP_SPLIT, pc1 = atom_start, pc2 = next_pc)]

# buildifier: disable=list-append
def _handle_quantifier(pattern, i, insts, atom_start = -1, ungreedy = False):
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
                if ungreedy:
                    is_lazy = not is_lazy

                template = insts[atom_start:]
                for _ in range(len(template)):
                    insts.pop()

                # Expand Min
                for _ in range(min_rep):
                    insts += _shift_insts(template, 0, len(insts))

                # Expand Max
                if max_rep == -1:
                    block_start = len(insts)
                    insts += _shift_insts(template, 0, block_start)
                    _apply_star(insts, block_start, lazy = is_lazy)

                elif max_rep > min_rep:
                    for _ in range(max_rep - min_rep):
                        block_start = len(insts)
                        insts += _shift_insts(template, 0, block_start)
                        _apply_question_mark(insts, block_start, lazy = is_lazy)

                return final_i

    # 2. Standard Quantifiers
    if next_char == "?":
        is_lazy, final_i = check_lazy(i + 1)
        if ungreedy:
            is_lazy = not is_lazy
        _apply_question_mark(insts, atom_start, lazy = is_lazy)
        return final_i
    elif next_char == "*":
        is_lazy, final_i = check_lazy(i + 1)
        if ungreedy:
            is_lazy = not is_lazy
        _apply_star(insts, atom_start, lazy = is_lazy)
        return final_i
    elif next_char == "+":
        is_lazy, final_i = check_lazy(i + 1)
        if ungreedy:
            is_lazy = not is_lazy
        _apply_plus(insts, atom_start, lazy = is_lazy)
        return final_i
    else:
        return i

# buildifier: disable=list-append
def compile_regex(pattern, start_group_id = 0):
    """Compiles regex to bytecode using Thompson NFA construction.

    Args:
      pattern: The regex pattern string.
      start_group_id: The starting ID for capturing groups.

    Returns:
      A tuple (instructions, named_groups_map, next_group_id, has_case_insensitive).
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
    ungreedy = False
    has_case_insensitive = False

    # Always save group 0 (full match) start
    instructions += [_inst(OP_SAVE, slot = 0)]

    # Root group to handle top-level alternations
    stack += [{
        "type": "root",
        "branch_starts": [len(instructions)],
        "exit_jumps": [],
        "flags": (case_insensitive, multiline, dot_all, ungreedy),
    }]

    pattern_len = len(pattern)
    for _ in range(pattern_len):
        if i >= pattern_len:
            break

        char = pattern[i]

        if char == "^":
            if multiline:
                instructions += [_inst(OP_ANCHOR_LINE_START)]
            else:
                instructions += [_inst(OP_ANCHOR_START)]

        elif char == "$":
            if multiline:
                instructions += [_inst(OP_ANCHOR_LINE_END)]
            else:
                instructions += [_inst(OP_ANCHOR_END)]

        elif char == "[":
            i += 1
            set_struct, is_negated, i = _compile_bracket_class(pattern, i, pattern_len, case_insensitive)

            if case_insensitive:
                has_case_insensitive = True
                instructions += [_inst(OP_SET, (set_struct, is_negated), is_ci = True)]
            else:
                instructions += [_inst(OP_SET, (set_struct, is_negated), is_ci = False)]
            i = _handle_quantifier(pattern, i, instructions)

        elif char == "(":
            saved_flags = (case_insensitive, multiline, dot_all, ungreedy)
            res = _parse_group_start(pattern, i, pattern_len, saved_flags)
            i = res.new_i
            is_capturing = res.is_capturing
            group_name = res.group_name
            is_group_start = res.is_group_start
            case_insensitive, multiline, dot_all, ungreedy = res.new_flags

            if is_group_start:
                gid = -1
                if is_capturing:
                    group_count += 1
                    gid = group_count
                    instructions += [_inst(OP_SAVE, slot = gid * 2)]
                    if group_name:
                        named_groups[group_name] = gid

                stack += [{
                    "type": "group",
                    "gid": gid,
                    "is_capturing": is_capturing,
                    "start_pc": len(instructions) - 1,
                    "branch_starts": [len(instructions)],
                    "exit_jumps": [],
                    "flags": saved_flags,
                }]

        elif char == ")":
            if stack:
                top = stack.pop()
                if top["type"] == "group":
                    if len(top["branch_starts"]) > 1:
                        top["exit_jumps"] += [len(instructions)]
                        instructions += [_inst(OP_JUMP, target = -1)]
                        _build_alt_tree(instructions, top)

                    for jump_idx in top["exit_jumps"]:
                        instructions[jump_idx] = _inst(OP_JUMP, target = len(instructions))

                    # Only emit SAVE if it was a capturing group
                    if top["is_capturing"]:
                        instructions += [_inst(OP_SAVE, slot = top["gid"] * 2 + 1)]

                    start_pc_fix = top["start_pc"]

                    # Restore flags
                    case_insensitive, multiline, dot_all, ungreedy = top["flags"]

                    i = _handle_quantifier(pattern, i, instructions, atom_start = start_pc_fix, ungreedy = ungreedy)

        elif char == "|":
            if stack:
                group_ctx = stack[-1]
                group_ctx["exit_jumps"] += [len(instructions)]
                instructions += [_inst(OP_JUMP, target = -1)]
                group_ctx["branch_starts"] += [len(instructions)]
            else:
                # Should not happen with root group
                instructions += [_inst(OP_CHAR, char, is_ci = False)]

        elif char == ".":
            if dot_all:
                instructions += [_inst(OP_ANY)]  # ANY (includes \n
            else:
                instructions += [_inst(OP_ANY_NO_NL)]  # ANY_NO_NL (excludes \n
            i = _handle_quantifier(pattern, i, instructions, ungreedy = ungreedy)

        elif char == "\\":
            if i + 1 < pattern_len:
                next_c = pattern[i + 1]
                if next_c == "A":
                    instructions += [_inst(OP_ANCHOR_START)]
                    i += 2
                    continue
                elif next_c == "z":
                    instructions += [_inst(OP_ANCHOR_END)]
                    i += 2
                    continue
                elif next_c == "Q":
                    # Quoted Literal \Q...\E
                    i += 2
                    found_e = False
                    for k in range(i, pattern_len - 1):
                        if pattern[k] == "\\" and pattern[k + 1] == "E":
                            # Match everything from i to k as literal
                            for j in range(i, k):
                                if case_insensitive:
                                    has_case_insensitive = True
                                    instructions += [_inst(OP_CHAR, val = pattern[j].lower(), is_ci = True)]
                                else:
                                    instructions += [_inst(OP_CHAR, val = pattern[j], is_ci = False)]
                            i = k + 2  # Skip \E
                            found_e = True
                            break
                    if not found_e:
                        # Match to end
                        for j in range(i, pattern_len):
                            if case_insensitive:
                                has_case_insensitive = True
                                instructions += [_inst(OP_CHAR, val = pattern[j].lower(), is_ci = True)]
                            else:
                                instructions += [_inst(OP_CHAR, val = pattern[j], is_ci = False)]
                        i = pattern_len
                    continue

            i += 1
            if i < pattern_len:
                next_c = pattern[i]

                # Check for shortcuts \d, \w, \s, \b, \B
                predef = _get_predefined_class(next_c)
                if predef:
                    # predef is (list, is_negated)
                    chars, is_negated = predef
                    builder = _new_set_builder(case_insensitive = case_insensitive)
                    for r_start, r_end in chars:
                        builder.add_range(r_start, r_end)
                    set_struct = builder.build()
                    if case_insensitive:
                        has_case_insensitive = True
                        instructions += [_inst(OP_SET, val = (set_struct, is_negated), is_ci = True)]
                    else:
                        instructions += [_inst(OP_SET, val = (set_struct, is_negated), is_ci = False)]
                elif next_c == "b":
                    instructions += [_inst(OP_WORD_BOUNDARY)]
                elif next_c == "B":
                    instructions += [_inst(OP_NOT_WORD_BOUNDARY)]
                else:
                    # Handle escapes
                    char, new_i = _parse_escape(pattern, i, pattern_len)
                    i = new_i

                    if case_insensitive:
                        has_case_insensitive = True
                        if char:
                            char = char.lower()
                        instructions += [_inst(OP_CHAR, val = char, is_ci = True)]
                    else:
                        instructions += [_inst(OP_CHAR, val = char, is_ci = False)]
                i = _handle_quantifier(pattern, i, instructions, ungreedy = ungreedy)

        else:
            if case_insensitive:
                has_case_insensitive = True
                instructions += [_inst(OP_CHAR, val = char.lower(), is_ci = True)]
            else:
                instructions += [_inst(OP_CHAR, val = char, is_ci = False)]
            i = _handle_quantifier(pattern, i, instructions, ungreedy = ungreedy)

        i += 1

    # Finalize root group (alternations)
    if stack:
        root = stack.pop()
        if root["type"] == "root":
            if len(root["branch_starts"]) > 1:
                root["exit_jumps"] += [len(instructions)]
                instructions += [_inst(OP_JUMP, target = -1)]
                _build_alt_tree(instructions, root)
                for jump_idx in root["exit_jumps"]:
                    instructions[jump_idx] = _inst(OP_JUMP, target = len(instructions))

    # Save group 0 end and match
    instructions += [_inst(OP_SAVE, slot = 1)]
    instructions += [_inst(OP_MATCH)]

    instructions = _optimize_bytecode(instructions)

    return instructions, named_groups, group_count, has_case_insensitive

def optimize_matcher(instructions):
    """Detects simple patterns that can be executed on a fast path.

    Args:
      instructions: The bytecode instructions.

    Returns:
      A struct containing optimization data, or None if no optimization is found.
    """
    if not instructions:
        return None

    # Pattern: ^literal...
    # instructions[0] is SAVE 0
    # check instructions[1]
    prefix = ""
    idx = 1
    case_insensitive_prefix = False

    # Check for anchors
    is_anchored_start = False
    if idx < len(instructions) and instructions[idx].op == OP_ANCHOR_START:
        is_anchored_start = True
        idx += 1

    all_ci = True
    all_cs = True

    # Collect prefix literals
    for _ in range(len(instructions)):
        if idx >= len(instructions):
            break
        inst = instructions[idx]
        itype = inst.op
        if itype == OP_CHAR:
            prefix += inst.val
            if inst.is_ci:
                all_cs = False
            else:
                all_ci = False
            idx += 1
        elif itype == OP_STRING:
            prefix += inst.val
            if inst.is_ci:
                all_cs = False
            else:
                all_ci = False
            idx += 1
        else:
            break

    if prefix != "":
        if all_ci:
            case_insensitive_prefix = True
        elif all_cs:
            case_insensitive_prefix = False
        else:
            # Mixed prefix - unsafe for simple case-insensitive fast path search
            # because .lower().find() will over-match.
            # Easiest is to disable prefix optimization if mixed, or just use CS search
            # which might miss matches but is at least safe from over-matching.
            # Better: if mixed, we can't use the simple string-based fast path safely
            # without VM confirmation.
            prefix = ""
            case_insensitive_prefix = False

    # After prefix, check for sets and loops
    prefix_set_chars = None
    greedy_set_chars = None
    is_greedy_case_insensitive = False

    if idx < len(instructions):
        inst = instructions[idx]
        itype = inst.op
        if itype in [OP_CHAR, OP_SET]:
            # Case 1: [set]+ or c+ -> ATOM, SPLIT(idx, idx+2)
            if idx + 1 < len(instructions):
                next_inst = instructions[idx + 1]
                if next_inst.op == OP_SPLIT and next_inst.pc1 == idx and next_inst.pc2 == idx + 2:
                    chars = None
                    is_ci = False
                    if itype == OP_CHAR:
                        chars = inst.val
                        is_ci = inst.is_ci
                    else:
                        set_data, is_negated = inst.val
                        is_ci = inst.is_ci
                        if not is_negated:
                            chars = set_data.all_chars

                    if chars != None:
                        prefix_set_chars = chars
                        greedy_set_chars = chars
                        is_greedy_case_insensitive = is_ci
                        idx += 2
                elif itype == OP_SET:
                    # Case 2: Just a match-one prefix set [set]
                    set_data, is_negated = inst.val
                    if not is_negated:
                        prefix_set_chars = set_data.all_chars
                        idx += 1
            elif itype == OP_SET:
                # Case 2 (at end): Just a match-one prefix set [set]
                set_data, is_negated = inst.val
                if not is_negated:
                    prefix_set_chars = set_data.all_chars
                    idx += 1

        elif itype == OP_GREEDY_LOOP:
            # Case 2b: Optimized Greedy Loop
            greedy_set_chars = inst.val
            is_greedy_case_insensitive = inst.is_ci
            idx += 1

        elif itype == OP_SPLIT:
            # Case 3: [set]* or c* loop
            if idx + 2 < len(instructions):
                split_inst = instructions[idx]
                if split_inst.pc1 == idx + 1 and split_inst.pc2 == idx + 3:
                    atom_inst = instructions[idx + 1]
                    end_inst = instructions[idx + 2]
                    is_loop = False
                    if end_inst.op == OP_JUMP and end_inst.target == idx:
                        is_loop = True
                    elif end_inst.op == OP_SPLIT and end_inst.pc1 == idx:
                        is_loop = True

                    if is_loop:
                        chars = None
                        is_ci = False
                        if atom_inst.op == OP_CHAR:
                            chars = atom_inst.val
                            is_ci = atom_inst.is_ci
                        elif atom_inst.op == OP_SET:
                            set_data, is_negated = atom_inst.val
                            is_ci = atom_inst.is_ci
                            if not is_negated:
                                chars = set_data.all_chars

                        if chars != None:
                            greedy_set_chars = chars
                            is_greedy_case_insensitive = is_ci
                            idx += 3

    # If we have a prefix_set but no greedy_set yet, check if a greedy_set follows
    # Example: ^\d\w*
    if prefix_set_chars != None and greedy_set_chars == None:
        if idx < len(instructions):
            inst = instructions[idx]
            if inst.op == OP_SPLIT:
                # Check for * loop
                if idx + 2 < len(instructions):
                    if inst.pc1 == idx + 1 and inst.pc2 == idx + 3:
                        atom_inst = instructions[idx + 1]
                        end_inst = instructions[idx + 2]
                        is_loop = False
                        if end_inst.op == OP_JUMP and end_inst.target == idx:
                            is_loop = True
                        elif end_inst.op == OP_SPLIT and end_inst.pc1 == idx:
                            is_loop = True

                        if is_loop:
                            chars = None
                            is_ci = False
                            if atom_inst.op == OP_CHAR:
                                chars = atom_inst.val
                                is_ci = atom_inst.is_ci
                            elif atom_inst.op == OP_SET:
                                set_data, is_negated = atom_inst.val
                                is_ci = atom_inst.is_ci
                                if not is_negated:
                                    chars = set_data.all_chars

                            if chars != None:
                                greedy_set_chars = chars
                                is_greedy_case_insensitive = is_ci
                                idx += 3

    # Collect suffix literals
    suffix = ""
    is_suffix_case_insensitive = False
    all_cs = True
    all_ci = True

    for _ in range(len(instructions)):
        if idx >= len(instructions):
            break
        inst = instructions[idx]
        itype = inst.op
        if itype == OP_CHAR:
            suffix += inst.val
            if inst.is_ci:
                all_cs = False
            else:
                all_ci = False
            idx += 1
        elif itype == OP_STRING:
            suffix += inst.val
            if inst.is_ci:
                all_cs = False
            else:
                all_ci = False
            idx += 1
        else:
            break

    if suffix != "":
        if all_cs:
            pass  # Standard CS suffix
        elif all_ci:
            is_suffix_case_insensitive = True
        else:
            # Mixed suffix - unsafe for clear search
            suffix = ""
            is_suffix_case_insensitive = False

    # Check for end anchor or save 1/match
    is_anchored_end = False

    # Skip trailing saves if searching for end
    temp_idx = idx
    for _ in range(len(instructions)):
        if temp_idx < len(instructions) and instructions[temp_idx].op == OP_SAVE:
            temp_idx += 1
        else:
            break

    if temp_idx < len(instructions) and instructions[temp_idx].op == OP_ANCHOR_END:
        is_anchored_end = True
        temp_idx += 1

    # Check if we reached the matching end: SAVE 1, MATCH
    for _ in range(len(instructions)):
        if temp_idx < len(instructions) and instructions[temp_idx].op == OP_SAVE:
            temp_idx += 1
        else:
            break

    # Calculate disjointness of suffix and greedy set
    is_suffix_disjoint = True
    if greedy_set_chars != None and len(suffix) > 0:
        for i in range(len(suffix)):
            if suffix[i] in greedy_set_chars:
                is_suffix_disjoint = False
                break

    if temp_idx < len(instructions) and instructions[temp_idx].op == OP_MATCH:
        return struct(
            prefix = prefix,
            case_insensitive_prefix = case_insensitive_prefix,
            prefix_set_chars = prefix_set_chars,
            greedy_set_chars = greedy_set_chars,
            is_greedy_case_insensitive = is_greedy_case_insensitive,
            suffix = suffix,
            is_anchored_start = is_anchored_start,
            is_anchored_end = is_anchored_end,
            is_suffix_disjoint = is_suffix_disjoint,
            is_suffix_case_insensitive = is_suffix_case_insensitive,
        )

    return None
