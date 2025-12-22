"""A Thompson NFA-based Regex Engine implemented in Starlark.

Supports a significant subset of RE2 syntax:
- Single-character: Literals, ., \\d, \\D, \\s, \\S, \\w, \\W, [[:class:]]
- Composites: xy, x|y
- Repetitions: x*, x+, x?, x{n,m}, x{n,}, x{n} (Greedy and Lazy)
- Grouping: (re), (?P<name>re), (?:re), (?flags), (?flags:re)
- Anchors: ^, $, \\A, \\z, \\b, \\B
- Flags: i (case-insensitive), m (multi-line), s (dot-all), U (ungreedy)
- Escapes: \\n, \\r, \\t, \\f, \\v, \\a, \\xHH, \\x{h...h}, \\OOO, \\Q...\\E

API Functions:
- compile(pattern): Compiles a regex pattern into a reusable object.
- search(pattern, text): Scan through string looking for the first match.
- match(pattern, text): Try to apply the pattern at the start of the string.
- fullmatch(pattern, text): Try to apply the pattern to the entire string.
- findall(pattern, text): Return all non-overlapping matches.
- sub(pattern, repl, text, count=0): Replace occurrences of the pattern.
- split(pattern, text, maxsplit=0): Split string by the occurrences of the pattern.

Match Object Properties:
- group(n): Returns one or more subgroups of the match.
- groups(default=None): Returns a tuple containing all the subgroups of the match.
- span(n): Returns a 2-tuple containing the (start, end) indices of the subgroup.
- lastindex: The integer index of the last matched capturing group.
- lastgroup: The name of the last matched capturing group.
"""

MAX_GROUP_NAME_LEN = 32

_CHR_LOOKUP = (
    "\000\001\002\003\004\005\006\007" +
    "\010\011\012\013\014\015\016\017" +
    "\020\021\022\023\024\025\026\027" +
    "\030\031\032\033\034\035\036\037" +
    "\040\041\042\043\044\045\046\047" +
    "\050\051\052\053\054\055\056\057" +
    "\060\061\062\063\064\065\066\067" +
    "\070\071\072\073\074\075\076\077" +
    "\100\101\102\103\104\105\106\107" +
    "\110\111\112\113\114\115\116\117" +
    "\120\121\122\123\124\125\126\127" +
    "\130\131\132\133\134\135\136\137" +
    "\140\141\142\143\144\145\146\147" +
    "\150\151\152\153\154\155\156\157" +
    "\160\161\162\163\164\165\166\167" +
    "\170\171\172\173\174\175\176\177" +
    "\200\201\202\203\204\205\206\207" +
    "\210\211\212\213\214\215\216\217" +
    "\220\221\222\223\224\225\226\227" +
    "\230\231\232\233\234\235\236\237" +
    "\240\241\242\243\244\245\246\247" +
    "\250\251\252\253\254\255\256\257" +
    "\260\261\262\263\264\265\266\267" +
    "\270\271\272\273\274\275\276\277" +
    "\300\301\302\303\304\305\306\307" +
    "\310\311\312\313\314\315\316\317" +
    "\320\321\322\323\324\325\326\327" +
    "\330\331\332\333\334\335\336\337" +
    "\340\341\342\343\344\345\346\347" +
    "\350\351\352\353\354\355\356\357" +
    "\360\361\362\363\364\365\366\367" +
    "\370\371\372\373\374\375\376\377"
)

def _chr(i):
    return _CHR_LOOKUP[i]

_ORD_LOOKUP = {_CHR_LOOKUP[i]: i for i in range(256)}

def _ord(c):
    return _ORD_LOOKUP[c]

# Types
_STRING_TYPE = type("")
_FUNCTION_TYPE = type(_ord)

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
OP_CHAR_I = 14  # Match character case-insensitively
OP_SET_I = 15  # Match set case-insensitively
OP_STRING = 16  # Match string literally
OP_STRING_I = 17  # Match string case-insensitively

def _is_word_char(c):
    """Returns True if c is [a-zA-Z0-9_]."""
    if c == None:
        return False
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"

_PREDEFINED_CLASSES = {
    "d": ([("0", "9")], False),
    "D": ([("0", "9")], True),
    "w": ([("a", "z"), ("A", "Z"), ("0", "9"), ("_", "_")], False),
    "W": ([("a", "z"), ("A", "Z"), ("0", "9"), ("_", "_")], True),
    "s": ([(" ", " "), ("\t", "\t"), ("\n", "\n"), ("\r", "\r"), ("\f", "\f"), ("\v", "\v")], False),
    "S": ([(" ", " "), ("\t", "\t"), ("\n", "\n"), ("\r", "\r"), ("\f", "\f"), ("\v", "\v")], True),
}

def _get_predefined_class(char):
    """Returns (set_definition, is_negated) for \\d, \\w, \\s, \\D, \\W, \\S."""
    return _PREDEFINED_CLASSES.get(char)

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

def _get_posix_class(name):
    """Returns the character set for a POSIX class name."""
    return _POSIX_CLASSES.get(name)

_SIMPLE_ESCAPES = {
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "f": "\f",
    "v": "\v",
    "a": "\007",
}

# buildifier: disable=list-append
# buildifier: disable=list-append
def _new_set_builder(case_insensitive = False):
    """Returns a builder for creating a character set struct."""
    state = {
        "lookup": {},
        "ranges": [],
        "negated_posix_list": [],
        "all_chars_list": [],
    }

    RANGE_EXPANSION_LIMIT = 512
    ALL_CHARS_STR_LIMIT = 2048

    def add_char(c):
        if case_insensitive:
            c = c.lower()
        state["lookup"][c] = True
        state["all_chars_list"] += [c]

    def add_range(start, end):
        start_code = _ord(start)
        end_code = _ord(end)
        dist = end_code - start_code

        if dist < RANGE_EXPANSION_LIMIT:
            for code in range(start_code, end_code + 1):
                c = _chr(code)
                if case_insensitive:
                    c = c.lower()
                state["lookup"][c] = True
                state["all_chars_list"] += [c]
        else:
            state["ranges"] += [(start, end)]

    def add_negated_posix(pset):
        # pset is a list of atoms (chars or ranges)
        state["negated_posix_list"] += [pset]

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

        return struct(
            lookup = state["lookup"],
            ranges = state["ranges"],
            negated_posix = state["negated_posix_list"],
            all_chars = all_chars_str,
        )

    return struct(
        add_char = add_char,
        add_range = add_range,
        add_negated_posix = add_negated_posix,
        build = build,
    )

def _char_in_set(set_struct, c):
    """Checks if character c is in the set_struct."""
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
                    return _chr(val), end_brace
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
                return _chr(int(hex_str, 16)), i + 2
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
        return _chr(int(oct_str, 8)), i + 1 + consumed

    # Look up simple escapes (\n, \r, etc.)
    if char in _SIMPLE_ESCAPES:
        return _SIMPLE_ESCAPES[char], i

    return char, i

# buildifier: disable=list-append
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

# buildifier: disable=list-append
def _compile_bracket_class(pattern, i, pattern_len, case_insensitive):
    """Compiles a [...] set expression.

    Returns (set_struct, is_negated, closing_bracket_index).
    """
    is_negated = False
    if i < pattern_len and pattern[i] == "^":
        is_negated = True
        i += 1

    builder = _new_set_builder(case_insensitive = case_insensitive)
    for _ in range(pattern_len):
        if i >= pattern_len or pattern[i] == "]":
            break

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

# buildifier: disable=list-append
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

            for _ in range(10):
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

# buildifier: disable=list-append
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
    ungreedy = False
    has_case_insensitive = False

    # Always save group 0 (full match) start
    instructions += [(OP_SAVE, 0, None, None)]

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
                instructions += [(OP_ANCHOR_LINE_START, None, None, None)]
            else:
                instructions += [(OP_ANCHOR_START, None, None, None)]

        elif char == "$":
            if multiline:
                instructions += [(OP_ANCHOR_LINE_END, None, None, None)]
            else:
                instructions += [(OP_ANCHOR_END, None, None, None)]

        elif char == "[":
            i += 1
            set_struct, is_negated, i = _compile_bracket_class(pattern, i, pattern_len, case_insensitive)

            if case_insensitive:
                has_case_insensitive = True
                instructions += [(OP_SET_I, (set_struct, is_negated), None, None)]
            else:
                instructions += [(OP_SET, (set_struct, is_negated), None, None)]
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
                    instructions += [(OP_SAVE, gid * 2, None, None)]
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
                        instructions += [(OP_JUMP, None, -1, None)]
                        _build_alt_tree(instructions, top)

                    for jump_idx in top["exit_jumps"]:
                        instructions[jump_idx] = (OP_JUMP, None, len(instructions), None)

                    # Only emit SAVE if it was a capturing group
                    if top["is_capturing"]:
                        instructions += [(OP_SAVE, top["gid"] * 2 + 1, None, None)]

                    start_pc_fix = top["start_pc"]

                    # Restore flags
                    case_insensitive, multiline, dot_all, ungreedy = top["flags"]

                    i = _handle_quantifier(pattern, i, instructions, atom_start = start_pc_fix, ungreedy = ungreedy)

        elif char == "|":
            if stack:
                group_ctx = stack[-1]
                group_ctx["exit_jumps"] += [len(instructions)]
                instructions += [(OP_JUMP, None, -1, None)]
                group_ctx["branch_starts"] += [len(instructions)]
            else:
                # Should not happen with root group
                instructions += [(OP_CHAR, char, None, None)]

        elif char == ".":
            if dot_all:
                instructions += [(OP_ANY, None, None, None)]  # ANY (includes \n
            else:
                instructions += [(OP_ANY_NO_NL, None, None, None)]  # ANY_NO_NL (excludes \n
            i = _handle_quantifier(pattern, i, instructions, ungreedy = ungreedy)

        elif char == "\\":
            if i + 1 < pattern_len:
                next_c = pattern[i + 1]
                if next_c == "A":
                    instructions += [(OP_ANCHOR_START, None, None, None)]
                    i += 2
                    continue
                elif next_c == "z":
                    instructions += [(OP_ANCHOR_END, None, None, None)]
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
                                    instructions += [(OP_CHAR_I, pattern[j].lower(), None, None)]
                                else:
                                    instructions += [(OP_CHAR, pattern[j], None, None)]
                            i = k + 2  # Skip \E
                            found_e = True
                            break
                    if not found_e:
                        # Match to end
                        for j in range(i, pattern_len):
                            if case_insensitive:
                                has_case_insensitive = True
                                instructions += [(OP_CHAR_I, pattern[j].lower(), None, None)]
                            else:
                                instructions += [(OP_CHAR, pattern[j], None, None)]
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
                        instructions += [(OP_SET_I, (set_struct, is_negated), None, None)]
                    else:
                        instructions += [(OP_SET, (set_struct, is_negated), None, None)]
                elif next_c == "b":
                    instructions += [(OP_WORD_BOUNDARY, None, None, None)]
                elif next_c == "B":
                    instructions += [(OP_NOT_WORD_BOUNDARY, None, None, None)]
                else:
                    # Handle escapes
                    char, new_i = _parse_escape(pattern, i, pattern_len)
                    i = new_i

                    if case_insensitive:
                        has_case_insensitive = True
                        if char:
                            char = char.lower()
                        instructions += [(OP_CHAR_I, char, None, None)]
                    else:
                        instructions += [(OP_CHAR, char, None, None)]
                i = _handle_quantifier(pattern, i, instructions, ungreedy = ungreedy)

        else:
            if case_insensitive:
                has_case_insensitive = True
                instructions += [(OP_CHAR_I, char.lower(), None, None)]
            else:
                instructions += [(OP_CHAR, char, None, None)]
            i = _handle_quantifier(pattern, i, instructions, ungreedy = ungreedy)

        i += 1

    # Finalize root group (alternations)
    if stack:
        root = stack.pop()
        if root["type"] == "root":
            if len(root["branch_starts"]) > 1:
                root["exit_jumps"] += [len(instructions)]
                instructions += [(OP_JUMP, None, -1, None)]
                _build_alt_tree(instructions, root)
                for jump_idx in root["exit_jumps"]:
                    instructions[jump_idx] = (OP_JUMP, None, len(instructions), None)

    # Save group 0 end and match
    instructions += [(OP_SAVE, 1, None, None)]
    instructions += [(OP_MATCH, None, None, None)]

    instructions = _optimize_bytecode(instructions)

    return instructions, named_groups, group_count, has_case_insensitive

# buildifier: disable=list-append
def _optimize_bytecode(instructions):
    """Merges consecutive characters into strings to speed up matching."""
    if not instructions:
        return []

    # 1. Find all jump targets to avoid merging across them
    targets = {0: True, len(instructions): True}
    for inst in instructions:
        itype, _, pc1, pc2 = inst
        if itype == OP_JUMP:
            targets[pc1] = True
        elif itype == OP_SPLIT:
            targets[pc1] = True
            targets[pc2] = True

    # 2. Merge consecutive chars
    new_insts = []
    old_to_new = {}

    num_insts = len(instructions)
    skip = 0
    for i in range(num_insts):
        if skip > 0:
            skip -= 1
            continue

        old_to_new[i] = len(new_insts)
        inst = instructions[i]
        itype, val, pc1, pc2 = inst

        if itype == OP_CHAR or itype == OP_CHAR_I:
            # Try to merge runs of the same character type that are not jump targets
            s = val
            j = i + 1

            # Simulation of while loop
            for _ in range(num_insts - i - 1):
                if j >= num_insts or (j in targets):
                    break
                next_inst = instructions[j]
                if next_inst[0] == itype:
                    s += next_inst[1]
                    j += 1
                else:
                    break

            if len(s) > 1:
                new_type = OP_STRING if itype == OP_CHAR else OP_STRING_I
                new_insts.append((new_type, s, None, None))
                skip = j - i - 1
                continue

        new_insts.append(inst)

    # Final "virtual" instruction for matches at the end
    old_to_new[num_insts] = len(new_insts)

    # Fill in holes in old_to_new (for merged instructions)
    # Jumps to a merged instruction should go to the next valid instruction
    # OR to the start of the merge. For now, let's map them to the next instruction.
    for i in range(num_insts - 1, -1, -1):
        if i not in old_to_new:
            old_to_new[i] = old_to_new[i + 1]

    # 3. Update PC offsets
    final_insts = []
    for inst in new_insts:
        itype, val, pc1, pc2 = inst
        new_pc1 = old_to_new[pc1] if pc1 != None else None
        new_pc2 = old_to_new[pc2] if pc2 != None else None
        final_insts.append((itype, val, new_pc1, new_pc2))

    return final_insts

# buildifier: disable=list-append
def _build_alt_tree(instructions, group_ctx):
    branches = group_ctx["branch_starts"]
    entry_pc = branches[0]
    orig_inst = instructions[entry_pc]
    relocated_pc = len(instructions)
    instructions += [orig_inst]
    instructions += [(OP_JUMP, None, entry_pc + 1, None)]

    tree_start_pc = len(instructions)
    current_branches = branches[:]
    current_branches[0] = relocated_pc

    for j in range(len(current_branches) - 1):
        if j < len(current_branches) - 2:
            next_split = len(instructions) + 1
            instructions += [(OP_SPLIT, None, current_branches[j], next_split)]
        else:
            instructions += [(OP_SPLIT, None, current_branches[j], current_branches[-1])]

    instructions[entry_pc] = (OP_JUMP, None, tree_start_pc, None)

# buildifier: disable=list-append
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
        new_block += [(code, val, pc1, pc2)]

    return new_block

# buildifier: disable=list-append
def _apply_question_mark(insts, atom_start, lazy = False):
    """Applies ? logic. Lazy=True tries skipping first."""
    jump_to_end_idx = len(insts)
    insts += [(OP_JUMP, None, -1, None)]
    orig_first = insts[atom_start]
    reloc_idx = len(insts)
    insts += [orig_first]
    if atom_start + 1 < jump_to_end_idx:
        insts += [(OP_JUMP, None, atom_start + 1, None)]
    skip_target = len(insts)

    # Greedy: Try reloc (match) then skip. Lazy: Try skip then reloc.
    if lazy:
        insts[atom_start] = (OP_SPLIT, None, skip_target, reloc_idx)
    else:
        insts[atom_start] = (OP_SPLIT, None, reloc_idx, skip_target)
    insts[jump_to_end_idx] = (OP_JUMP, None, skip_target, None)

# buildifier: disable=list-append
def _apply_star(insts, atom_start, lazy = False):
    """Applies * logic. Lazy=True tries skipping first."""
    orig_first = insts[atom_start]
    reloc_idx = len(insts)
    insts += [orig_first]
    if len(insts) - 1 > atom_start + 1:
        insts += [(3, None, atom_start + 1, None)]
    insts += [(OP_JUMP, None, atom_start, None)]
    skip_target = len(insts)

    # Greedy: Try reloc (loop) then skip. Lazy: Try skip then reloc.
    if lazy:
        insts[atom_start] = (OP_SPLIT, None, skip_target, reloc_idx)
    else:
        insts[atom_start] = (OP_SPLIT, None, reloc_idx, skip_target)

# buildifier: disable=list-append
def _apply_plus(insts, atom_start, lazy = False):
    """Applies + logic. Lazy=True tries exit first."""

    # Greedy: atom -> SPLIT(atom_start, next)
    # Lazy: atom -> SPLIT(next, atom_start)
    next_pc = len(insts) + 1
    if lazy:
        insts += [(OP_SPLIT, None, next_pc, atom_start)]
    else:
        insts += [(OP_SPLIT, None, atom_start, next_pc)]

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
                    _copy_insts(template, 0, len(insts))
                    curr_start = len(insts)
                    delta = curr_start - atom_start
                    for op in template:
                        code, val, pc1, pc2 = op
                        if pc1 != None and pc1 >= atom_start:
                            pc1 += delta
                        if pc2 != None and pc2 >= atom_start:
                            pc2 += delta
                        insts += [(code, val, pc1, pc2)]

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
                        insts += [(code, val, pc1, pc2)]
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
                            insts += [(code, val, pc1, pc2)]
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
def _get_epsilon_closure(instructions, input_str, input_len, start_pc, start_regs, current_idx, visited, visited_gen):
    reachable = []
    num_inst = len(instructions)

    # Thompson NFA: The first time we reach a PC, it's via the highest priority path.
    stack = [(start_pc, start_regs)]

    # Outer loop handles exploration from stack.
    # Inner loop follows single-thread transitions.
    limit = num_inst * 2 + 100
    inner_limit = num_inst + 10

    for _ in range(limit):
        if not stack:
            break
        pc, regs = stack.pop()

        # Inner loop to follow a thread's epsilon transitions.
        for _ in range(inner_limit):
            if pc >= num_inst:
                break

            # Deduplication: the first time we reach a state in this generation,
            # it's via the highest-priority path currently available.
            if visited[pc] == visited_gen:
                # print("DEBUG: closure pc=%d ALREADY VISITED (gen=%d)" % (pc, visited_gen))
                break
            visited[pc] = visited_gen
            # print("DEBUG: closure pc=%d visited" % pc)

            inst = instructions[pc]
            itype = inst[0]

            if itype == OP_SPLIT:
                # Priority: pc1 then pc2. Push pc2 (lower priority) to stack.
                pc1, pc2 = inst[2], inst[3]
                if pc2 < num_inst:
                    stack.append((pc2, regs[:]))
                if pc1 < num_inst:
                    pc = pc1  # Continue inner loop with higher priority
                else:
                    break
            elif itype == OP_JUMP:
                pc = inst[2]
            elif itype == OP_SAVE:
                reg_idx = inst[1]
                regs[reg_idx] = current_idx
                if reg_idx > 1 and reg_idx % 2 == 1:
                    regs[-1] = reg_idx // 2
                pc += 1
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
            elif itype == OP_WORD_BOUNDARY or itype == OP_NOT_WORD_BOUNDARY:
                is_prev_word = (current_idx > 0 and _is_word_char(input_str[current_idx - 1]))
                is_curr_word = (current_idx < input_len and _is_word_char(input_str[current_idx]))
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
            else:
                # Not an epsilon instruction (e.g. OP_CHAR, OP_MATCH, OP_SET, OP_STRING)
                # print("DEBUG: closure reached non-epsilon pc=%d" % pc)
                reachable += [(pc, regs)]
                break

    return reachable

# buildifier: disable=list-append
def _process_batch(instructions, batch, char, char_lower, char_idx, input_str):
    """Processes a batch of threads against the current character.

    Returns (next_threads, match_regs).
    """

    next_threads_dict = {}  # pc -> regs (deduplication)
    next_threads_list = []  # order preserved
    match_regs = None

    # Sort batch by rank to preserve priority
    # Rank is a tuple: (start_index, nfa_order)
    # Starlark sort is stable.
    # Higher priority (lower rank) threads first.
    sorted_batch = sorted(batch, key = lambda t: t[2])

    for pc, regs, rank in sorted_batch:
        inst = instructions[pc]
        itype = inst[0]

        if itype == OP_MATCH:
            if match_regs == None:
                match_regs = regs
            break

        if char == None and itype != OP_MATCH:
            continue

        match_found = False
        target_idx = char_idx + 1

        if itype == OP_CHAR:
            match_found = (inst[1] == char)
        elif itype == OP_CHAR_I:
            match_found = (inst[1] == char_lower)
        elif itype == OP_STRING:
            s = inst[1]
            s_len = len(s)
            if input_str[char_idx:char_idx + s_len] == s:
                match_found = True
                target_idx = char_idx + s_len
        elif itype == OP_STRING_I:
            s_lower = inst[1]
            s_len = len(s_lower)
            if input_str[char_idx:char_idx + s_len].lower() == s_lower:
                match_found = True
                target_idx = char_idx + s_len
        elif itype == OP_ANY:
            match_found = True
        elif itype == OP_ANY_NO_NL:
            match_found = (char != "\n")
        elif itype == OP_SET:
            set_struct, is_negated = inst[1]
            match_found = (_char_in_set(set_struct, char) != is_negated)
        elif itype == OP_SET_I:
            set_struct, is_negated = inst[1]
            match_found = (_char_in_set(set_struct, char_lower) != is_negated)

        if match_found:
            # Important: just add the raw next pc.
            # _execute_core will expand its epsilon closure at the correct char_idx.
            if pc + 1 not in next_threads_dict:
                next_threads_dict[pc + 1] = regs
                next_threads_list += [(pc + 1, regs, rank, target_idx)]

    return next_threads_list, match_regs

# buildifier: disable=list-append
def _execute_core(instructions, input_str, num_regs, start_index = 0, initial_regs = None, anchored = False, has_case_insensitive = False):
    if initial_regs == None:
        initial_regs = [-1] * (num_regs + 1)  # +1 for lastindex

    input_len = len(input_str)
    input_lower = None
    if has_case_insensitive:
        input_lower = input_str.lower()

    # Shared visited array for epsilon closure to avoid re-allocation
    visited = [0] * len(instructions)
    visited_gen = 1

    # future_threads maps target_idx -> list of (pc, regs, rank)
    future_threads = {}

    # Initialize with the start condition
    # Rank is a tuple to maintain priority.
    # Higher priority threads have lower rank (lexicographical).
    future_threads[start_index] = [(0, initial_regs, (start_index,))]

    match_regs = None

    # Main Loop: Iterate over input string
    for char_idx in range(start_index, input_len + 1):
        char = input_str[char_idx] if char_idx < input_len else None
        char_lower = None
        if input_lower != None and char_idx < input_len:
            char_lower = input_lower[char_idx]

        # 1. Get threads scheduled for this index
        current_threads = []
        visited_gen += 1

        # Populate current_threads from future_threads
        # Rank counter for re-normalization to prevent tuple explosion
        rank_counter = 0

        # Populate current_threads from future_threads
        if char_idx in future_threads:
            # Sort by rank to ensure priority is respected during epsilon closure expansion
            pending = sorted(future_threads.pop(char_idx), key = lambda t: t[2])
            for pc, regs, old_rank in pending:
                # Call epsilon closure to expand this thread at the current index
                closure = _get_epsilon_closure(instructions, input_str, input_len, pc, regs, char_idx, visited, visited_gen)

                # Assign new ranks preserving start_index and using counter for relative priority
                start_index = old_rank[0]
                for c_pc, c_regs in closure:
                    current_threads.append((c_pc, c_regs, (start_index, rank_counter)))
                    rank_counter += 1

        # 2. Unanchored Search Injection
        if not anchored:
            # Check if PC 0 is already in visited for this generation
            if visited[0] != visited_gen:
                closure_pc0 = _get_epsilon_closure(instructions, input_str, input_len, 0, initial_regs[:], char_idx, visited, visited_gen)

                # Unanchored start gets rank (char_idx, counter)
                # Since char_idx is the start index for this new thread.
                for c_pc, c_regs in closure_pc0:
                    current_threads.append((c_pc, c_regs, (char_idx, rank_counter)))
                    rank_counter += 1

        # Optimization: Stop early if no threads left
        if not current_threads and not future_threads:
            if match_regs or anchored or char_idx >= input_len:
                break

        # 3. Process current threads
        # 3. Process current threads
        res_future_list, batch_match = _process_batch(
            instructions,
            current_threads,
            char,
            char_lower,
            char_idx,
            input_str,
        )

        if batch_match:
            if match_regs == None:
                match_regs = batch_match
            elif batch_match[0] <= match_regs[0]:
                match_regs = batch_match

        # 4. Schedule future matches
        for pc, regs, rank, target_idx in res_future_list:
            if target_idx not in future_threads:
                future_threads[target_idx] = []
            future_threads[target_idx] += [(pc, regs, rank)]

    return match_regs

def _execute(instructions, input_str, num_regs, start_index = 0, initial_regs = None, anchored = False, has_case_insensitive = False):
    return _execute_core(instructions, input_str, num_regs, start_index, initial_regs, anchored, has_case_insensitive)

# buildifier: disable=list-append
def _expand_replacement(repl, match_str, groups, named_groups = {}):
    """Expands backreferences in replacement string."""

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

def _optimize_matcher(instructions):
    """Detects simple patterns that can be executed on a fast path."""
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
    if idx < len(instructions) and instructions[idx][0] == OP_ANCHOR_START:
        is_anchored_start = True
        idx += 1

    # Collect prefix literals
    for _ in range(len(instructions)):
        if idx >= len(instructions):
            break
        itype = instructions[idx][0]
        if itype == OP_CHAR:
            prefix += instructions[idx][1]
            idx += 1
        elif itype == OP_STRING:
            prefix += instructions[idx][1]
            idx += 1
        elif itype == OP_CHAR_I:
            prefix += instructions[idx][1]
            case_insensitive_prefix = True
            idx += 1
        elif itype == OP_STRING_I:
            prefix += instructions[idx][1]
            case_insensitive_prefix = True
            idx += 1
        else:
            break

    # After prefix, check for sets and loops
    prefix_set_chars = None
    greedy_set_chars = None

    if idx < len(instructions):
        itype = instructions[idx][0]
        if itype in [OP_CHAR, OP_CHAR_I, OP_SET, OP_SET_I]:
            # Case 1: [set]+ or c+ -> ATOM, SPLIT(idx, idx+2)
            if idx + 1 < len(instructions) and instructions[idx + 1][0] == OP_SPLIT and instructions[idx + 1][2] == idx and instructions[idx + 1][3] == idx + 2:
                chars = None
                if itype in [OP_CHAR, OP_CHAR_I]:
                    chars = instructions[idx][1]
                else:
                    set_data, is_negated = instructions[idx][1]
                    if not is_negated:
                        chars = set_data.all_chars

                if chars != None:
                    prefix_set_chars = chars
                    greedy_set_chars = chars
                    idx += 2
            elif itype in [OP_SET, OP_SET_I]:
                # Case 2: Just a match-one prefix set [set]
                set_data, is_negated = instructions[idx][1]
                if not is_negated:
                    prefix_set_chars = set_data.all_chars
                    idx += 1
            else:
                # Just a single char, already handled by prefix literal collector above if it was at start
                pass

        elif itype == OP_SPLIT:
            # Case 3: [set]* or c* loop -> SPLIT(idx+1, idx+3), ATOM, JUMP idx
            if idx + 2 < len(instructions) and instructions[idx][2] == idx + 1 and instructions[idx][3] == idx + 3:
                atom_inst = instructions[idx + 1]
                jump_inst = instructions[idx + 2]
                if jump_inst[0] == OP_JUMP and jump_inst[2] == idx:
                    chars = None
                    if atom_inst[0] in [OP_CHAR, OP_CHAR_I]:
                        chars = atom_inst[1]
                    elif atom_inst[0] in [OP_SET, OP_SET_I]:
                        set_data, is_negated = atom_inst[1]
                        if not is_negated:
                            chars = set_data.all_chars

                    if chars != None:
                        greedy_set_chars = chars
                        idx += 3

    # If we have a prefix_set but no greedy_set yet, check if a greedy_set follows
    # Example: ^\d\w*
    if prefix_set_chars != None and greedy_set_chars == None:
        if idx < len(instructions) and instructions[idx][0] == OP_SPLIT:
            # Check for * loop: SPLIT(idx+1, idx+3), ATOM, JUMP idx
            if idx + 2 < len(instructions) and instructions[idx][2] == idx + 1 and instructions[idx][3] == idx + 3:
                atom_inst = instructions[idx + 1]
                jump_inst = instructions[idx + 2]
                if jump_inst[0] == OP_JUMP and jump_inst[2] == idx:
                    chars = None
                    if atom_inst[0] in [OP_CHAR, OP_CHAR_I]:
                        chars = atom_inst[1]
                    elif atom_inst[0] in [OP_SET, OP_SET_I]:
                        set_data, is_negated = atom_inst[1]
                        if not is_negated:
                            chars = set_data.all_chars

                    if chars != None:
                        greedy_set_chars = chars
                        idx += 3

    # Collect suffix literals
    suffix = ""
    for _ in range(len(instructions)):
        if idx >= len(instructions):
            break
        itype = instructions[idx][0]
        if itype == OP_CHAR:
            suffix += instructions[idx][1]
            idx += 1
        elif itype == OP_STRING:
            suffix += instructions[idx][1]
            idx += 1
        else:
            break

    # Check for end anchor
    is_anchored_end = False
    if idx < len(instructions) and instructions[idx][0] == OP_ANCHOR_END:
        is_anchored_end = True
        idx += 1

    # Check if we reached the matching end: SAVE 1, MATCH
    if idx + 1 < len(instructions):
        if instructions[idx][0] == OP_SAVE and instructions[idx][1] == 1:
            if instructions[idx + 1][0] == OP_MATCH:
                return struct(
                    prefix = prefix,
                    case_insensitive_prefix = case_insensitive_prefix,
                    prefix_set_chars = prefix_set_chars,
                    greedy_set_chars = greedy_set_chars,
                    suffix = suffix,
                    is_anchored_start = is_anchored_start,
                    is_anchored_end = is_anchored_end,
                )

    return None

def _search_regs(bytecode, text, group_count, start_index = 0, has_case_insensitive = False):
    num_regs = (group_count + 1) * 2
    return _execute(bytecode, text, num_regs, start_index = start_index, anchored = False, has_case_insensitive = has_case_insensitive)

def _match_regs(bytecode, text, group_count, start_index = 0, has_case_insensitive = False):
    num_regs = (group_count + 1) * 2
    return _execute(bytecode, text, num_regs, start_index = start_index, anchored = True, has_case_insensitive = has_case_insensitive)

def _fullmatch_regs(bytecode, text, group_count, start_index = 0, has_case_insensitive = False):
    num_regs = (group_count + 1) * 2
    regs = _execute(bytecode, text, num_regs, start_index = start_index, anchored = True, has_case_insensitive = has_case_insensitive)
    if regs and regs[1] != len(text):
        return None
    return regs

def _search_bytecode(bytecode, text, named_groups, group_count, start_index = 0, has_case_insensitive = False, opt = None):
    # Fast path optimization
    if opt and not has_case_insensitive:
        if opt.is_anchored_start:
            # If anchored at start, search is just match
            return _match_bytecode(bytecode, text, named_groups, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive, opt = opt)

        if opt.is_anchored_end:
            # Case: ...sets...suffix$
            if text.endswith(opt.suffix):
                # Work backwards from the suffix
                before_suffix_idx = len(text) - len(opt.suffix)

                # Use rstrip to find where the greedy set starts
                if opt.greedy_set_chars != None:
                    prefix_plus_middle = text[:before_suffix_idx]
                    stripped = prefix_plus_middle.rstrip(opt.greedy_set_chars)
                    greedy_start = len(stripped)
                else:
                    greedy_start = before_suffix_idx

                # Check prefix_set_chars (one char)
                match_start = greedy_start
                prefix_ok = True
                if opt.prefix_set_chars != None:
                    if match_start > 0 and text[match_start - 1] in opt.prefix_set_chars:
                        match_start -= 1
                    else:
                        prefix_ok = False

                # Check prefix literal
                if prefix_ok:
                    if text[:match_start].endswith(opt.prefix):
                        match_start -= len(opt.prefix)

                        # Validate that we matched at least one char if it was a + loop
                        # Wait, _optimize_matcher sets both prefix_set and greedy_set for +.
                        # So if prefix_set was matched, we are good.

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
                        return _MatchObject(text, regs, compiled, start_index, len(text))

        # General case search optimization: skipping to prefix or suffix
        if opt.prefix != "":
            start_off = start_index

            # We can use find() to skip to the first potential match
            for _ in range(len(text)):  # Loop for find() calls
                found_idx = text.find(opt.prefix, start_off)
                if found_idx == -1:
                    break

                # For unanchored search with prefix literal, simple skip:
                regs = _match_regs(bytecode, text, group_count, start_index = found_idx, has_case_insensitive = has_case_insensitive)
                if regs:
                    compiled = struct(
                        bytecode = bytecode,
                        named_groups = named_groups,
                        group_count = group_count,
                        pattern = None,
                        has_case_insensitive = has_case_insensitive,
                        opt = opt,
                    )
                    return _MatchObject(text, regs, compiled, start_index, len(text))

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
                regs = _match_regs(bytecode, text, group_count, start_index = search_start, has_case_insensitive = has_case_insensitive)
                if regs:
                    compiled = struct(
                        bytecode = bytecode,
                        named_groups = named_groups,
                        group_count = group_count,
                        pattern = None,
                        has_case_insensitive = has_case_insensitive,
                        opt = opt,
                    )
                    return _MatchObject(text, regs, compiled, start_index, len(text))

                # If no match found yet, move past this suffix
                start_off = found_idx + 1
                if start_off > len(text):
                    break

            return None

    regs = _search_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive)
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
    return _MatchObject(text, regs, compiled, start_index, len(text))

def _match_bytecode(bytecode, text, named_groups, group_count, start_index = 0, has_case_insensitive = False, opt = None):
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
                return _MatchObject(text, regs, compiled, start_index, len(text))

    regs = _match_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive)
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
    return _MatchObject(text, regs, compiled, start_index, len(text))

def _fullmatch_bytecode(bytecode, text, named_groups, group_count, start_index = 0, has_case_insensitive = False, opt = None):
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
                return _MatchObject(text, regs, compiled, start_index, len(text))

    regs = _fullmatch_regs(bytecode, text, group_count, start_index = start_index, has_case_insensitive = has_case_insensitive)
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
    return _MatchObject(text, regs, compiled, start_index, len(text))

def compile(pattern):
    """Compiles a regex pattern into a reusable object.

    Args:
      pattern: The regex pattern string.

    Returns:
      A struct containing the compiled bytecode and methods.
    """
    if hasattr(pattern, "bytecode"):
        return pattern

    bytecode, named_groups, group_count, has_case_insensitive = _compile_regex(pattern)
    opt = _optimize_matcher(bytecode)

    def _search(text):
        return _search_bytecode(bytecode, text, named_groups, group_count, has_case_insensitive = has_case_insensitive)

    def _match(text):
        return _match_bytecode(bytecode, text, named_groups, group_count, has_case_insensitive = has_case_insensitive, opt = opt)

    def _fullmatch(text):
        return _fullmatch_bytecode(bytecode, text, named_groups, group_count, has_case_insensitive = has_case_insensitive)

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
      A dictionary containing the match results (group ID/name -> matched string),
      or None if no match was found.
    """
    compiled = compile(pattern)
    return _search_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = 0, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt)

def match(pattern, text):
    """Try to apply the pattern at the start of the string.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.

    Returns:
      A dictionary containing the match results (group ID/name -> matched string),
      or None if no match was found.
    """
    compiled = compile(pattern)
    return _match_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = 0, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt)

def fullmatch(pattern, text):
    """Try to apply the pattern to the entire string.

    Args:
      pattern: The regex pattern string or a compiled regex object.
      text: The text to match against.

    Returns:
      A dictionary containing the match results (group ID/name -> matched string),
      or None if no match was found.
    """
    compiled = compile(pattern)
    return _fullmatch_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = 0, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt)

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

    # Simulate while loop
    # Max possible matches is len(text) + 1 (for empty matches)
    for _ in range(text_len + 2):
        m = _search_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = start_index, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt)
        if not m:
            break

        match_start = m.start()
        match_end = m.end()

        if match_start == -1:
            # Should not happen if execute returns non-None
            break

        # Extract result
        if group_count == 0:
            matches += [text[match_start:match_end]]
        else:
            # Return groups
            matches += [m.groups(default = None)]

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
def _MatchObject(text, regs, compiled, pos, endpos):
    """Constructs a match object with methods.

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

    # Reuse findall logic but we need the match objects (start/end indices)
    # findall returns strings/tuples, which loses index info.
    # So we duplicate the loop here or refactor findall to return match objects.
    # Let's duplicate loop for now to avoid breaking findall API.

    res_parts = []
    last_idx = 0
    start_index = 0
    text_len = len(text)
    matches_found = 0

    # Simulate while loop
    for _ in range(text_len + 2):
        if count > 0 and matches_found >= count:
            break

        m = _search_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = start_index, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt)
        if not m:
            break

        match_start = m.start()
        match_end = m.end()

        # Append text before match
        res_parts += [text[last_idx:match_start]]

        # Calculate replacement
        match_str = text[match_start:match_end]

        groups = m.groups(default = None)

        if type(repl) == _FUNCTION_TYPE:
            # m is already a MatchObject-like struct
            replacement = repl(m)
        else:
            replacement = _expand_replacement(repl, match_str, groups, compiled.named_groups)

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

    # Simulate while loop
    for _ in range(text_len + 2):
        if maxsplit > 0 and splits_found >= maxsplit:
            break

        m = _search_bytecode(compiled.bytecode, text, compiled.named_groups, compiled.group_count, start_index = start_index, has_case_insensitive = compiled.has_case_insensitive, opt = compiled.opt)
        if not m:
            break

        match_start = m.start()
        match_end = m.end()

        if match_start == -1:
            break

        # Append text before match
        res_parts += [text[last_idx:match_start]]

        # If capturing groups, append them too (Python behavior)
        if compiled.group_count > 0:
            for i in range(1, compiled.group_count + 1):
                res_parts += [m.group(i)]

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
