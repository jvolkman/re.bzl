"""Constants for Starlark Regex Engine."""

MAX_GROUP_NAME_LEN = 32

# Bytecode Instructions

# Match specific character
# Format: (op, val, is_ci, None)
OP_CHAR = 0

# Match any character (including \n)
# Format: (op, None, None, None)
OP_ANY = 1

# Jump to pc1 or pc2 (Thompson NFA choice)
# Format: (op, None, pc1, pc2)
OP_SPLIT = 2

# Jump to pc
# Format: (op, None, target, None)
OP_JUMP = 3

# Save current index to group slot
# Format: (op, None, slot, None)
OP_SAVE = 4

# Match success
# Format: (op, None, None, None)
OP_MATCH = 5

# Match any character in a set (char class)
# Format: (op, (set_struct, is_negated), is_ci, None)
OP_SET = 6

# Match absolute start of input
# Format: (op, None, None, None)
OP_ANCHOR_START = 7

# Match absolute end of input
# Format: (op, None, None, None)
OP_ANCHOR_END = 8

# Match a word boundary (\b)
# Format: (op, None, None, None)
OP_WORD_BOUNDARY = 9

# Match a non-word boundary (\B)
# Format: (op, None, None, None)
OP_NOT_WORD_BOUNDARY = 10

# Match any character EXCEPT \n
# Format: (op, None, None, None)
OP_ANY_NO_NL = 11

# Match start of line or after \n
# Format: (op, None, None, None)
OP_ANCHOR_LINE_START = 12

# Match end of line or before \n
# Format: (op, None, None, None)
OP_ANCHOR_LINE_END = 13

# Match string literally
# Format: (op, val, is_ci, None)
OP_STRING = 14

# Optimization: Greedy loop for character/set
# Format: (op, val, exit_pc, is_ci)
OP_GREEDY_LOOP = 15

# Optimization: Ungreedy loop for character/set
# Format: (op, val, exit_pc, is_ci)
OP_UNGREEDY_LOOP = 16

# Flags
I = 2  # buildifier: disable=confusing-name
IGNORECASE = I
M = 8
MULTILINE = M
S = 16
DOTALL = S
U = 32
UNICODE = U
X = 64
VERBOSE = X
UNGREEDY = 128

CHR_LOOKUP = (
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

ORD_LOOKUP = {CHR_LOOKUP[i]: i for i in range(256)}
