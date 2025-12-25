"""
Public API for the Starlark regex engine.
"""

load("//re/private:constants.bzl", _DOTALL = "DOTALL", _I = "I", _IGNORECASE = "IGNORECASE", _M = "M", _MULTILINE = "MULTILINE", _S = "S", _U = "U", _UNGREEDY = "UNGREEDY", _UNICODE = "UNICODE", _VERBOSE = "VERBOSE", _X = "X")
load("//re/private:re.bzl", _compile = "compile", _findall = "findall", _fullmatch = "fullmatch", _match = "match", _search = "search", _split = "split", _sub = "sub")

# Re-export flags
I = _I
M = _M
S = _S
U = _U
X = _X
IGNORECASE = _IGNORECASE
MULTILINE = _MULTILINE
DOTALL = _DOTALL
UNICODE = _UNICODE
VERBOSE = _VERBOSE
UNGREEDY = _UNGREEDY

# Export functions
compile = _compile
findall = _findall
fullmatch = _fullmatch
match = _match
search = _search
split = _split
sub = _sub

# Export as a struct
re = struct(
    compile = _compile,
    findall = _findall,
    fullmatch = _fullmatch,
    match = _match,
    search = _search,
    split = _split,
    sub = _sub,
    I = _I,
    M = _M,
    S = _S,
    U = _U,
    X = _X,
    IGNORECASE = _IGNORECASE,
    MULTILINE = _MULTILINE,
    DOTALL = _DOTALL,
    UNICODE = _UNICODE,
    VERBOSE = _VERBOSE,
    UNGREEDY = _UNGREEDY,
)
