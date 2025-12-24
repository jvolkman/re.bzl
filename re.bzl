"""
Public API for the Starlark regex engine.
"""

load("//re:re.bzl", _compile = "compile", _findall = "findall", _fullmatch = "fullmatch", _match = "match", _search = "search", _split = "split", _sub = "sub")

# Export functions directly
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
)
