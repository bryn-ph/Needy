"""Syntax-check every addon Lua file with Lua 5.1, and catch backslash escapes Lua silently drops."""
import pathlib, sys
from lupa import lua51

root = pathlib.Path(__file__).resolve().parents[1]
addon = root / "Needy"
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
check = lua.eval("function(src, name) local f, err = loadstring(src, name); return f ~= nil, err end")

VALID_ESCAPES = set("abfnrtv\\\"'\n0123456789")


def bad_escapes(src):
    r"""Backslash escapes Lua 5.1 silently drops ("Interface\Buttons" -> "InterfaceButtons")."""
    i, line = 0, 1
    while i < len(src):
        c = src[i]
        if c == "\n":
            line += 1
        if src.startswith("--", i):
            while i < len(src) and src[i] != "\n":
                i += 1
            continue
        if src.startswith("[[", i) or src.startswith("[=", i):
            level = 0
            while src[i + 1 + level] == "=":
                level += 1
            close = "]" + "=" * level + "]"
            end = src.find(close, i + 2 + level)
            end = len(src) if end < 0 else end
            line += src.count("\n", i, end)
            i = end + len(close)
            continue
        if c in "\"'":
            j = i + 1
            while j < len(src) and src[j] != c and src[j] != "\n":
                if src[j] == "\\":
                    if j + 1 < len(src) and src[j + 1] not in VALID_ESCAPES:
                        yield line, "\\" + src[j + 1]
                    j += 2
                    continue
                j += 1
            i = j + 1
            continue
        i += 1


ok = True
for p in sorted(addon.rglob("*.lua")):
    src = p.read_text(encoding="utf-8")
    good, err = check(src, "@" + str(p.relative_to(root)))
    if good:
        bad = list(bad_escapes(src))
        if bad:
            good, err = False, "; ".join(f"line {n}: {esc} is dropped by Lua" for n, esc in bad)
    print(("OK   " if good else "FAIL ") + str(p.relative_to(root)) + ("" if good else f"  {err}"))
    ok &= bool(good)
if not ok:
    sys.exit(1)
print("Syntax checks passed")
