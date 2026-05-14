from __future__ import annotations

from pathlib import Path
import re
import sys


KEY_CHARS = r"A-Za-z0-9_.:/+-"
KEY_LINE_RE = re.compile(rf"^(\s*)\{{\\DIF(?:add|del)\{{([{KEY_CHARS}]+)\}}\}}(\s*)$")
DELETED_BIBITEM_LINE_RE = re.compile(
    r"\\DIFdelbegin\s*%DIFDELCMD <\s*\\bibitem[^\n]*?%%%[^\n]*(?:\n|$)"
)


def _strip_diff_header_markup(text: str) -> str:
    text = DELETED_BIBITEM_LINE_RE.sub("", text)
    text = re.sub(r"%DIFDELCMD <[^\n]*(?:\n|$)", "", text)
    text = re.sub(r"%DIF\s*>[^\n]*(?:\n|$)", "\n", text)
    text = re.sub(r"\\DIF(?:add|del)(?:begin|end)\b\s*", "", text)
    text = re.sub(r"\\DIF(?:add|del)\{([^{}]*)\}", r"\1", text)
    text = re.sub(r"\s*%+\s*(?=\n|$)", "\n", text)
    return text


def _find_optional_end(text: str, start: int) -> int | None:
    depth = 1
    brace_depth = 0
    i = start + 1
    while i < len(text):
        char = text[i]
        previous = text[i - 1] if i > 0 else ""
        escaped = previous == "\\"
        if not escaped:
            if char == "{":
                brace_depth += 1
            elif char == "}" and brace_depth > 0:
                brace_depth -= 1
            elif char == "[" and brace_depth == 0:
                depth += 1
            elif char == "]" and brace_depth == 0:
                depth -= 1
                if depth == 0:
                    return i + 1
        i += 1
    return None


def _find_bibitem_key(cleaned: str) -> tuple[int, int, str, int, int] | None:
    bib_start = cleaned.find(r"\bibitem")
    if bib_start < 0:
        return None

    i = bib_start + len(r"\bibitem")
    while i < len(cleaned) and cleaned[i].isspace():
        i += 1

    if i < len(cleaned) and cleaned[i] == "[":
        optional_end = _find_optional_end(cleaned, i)
        if optional_end is None:
            return None
        i = optional_end

    while i < len(cleaned) and (cleaned[i].isspace() or cleaned[i] == "%"):
        i += 1

    key_match = re.match(rf"\{{([{KEY_CHARS}]+)\}}", cleaned[i:])
    if key_match is None:
        return None

    key_start = i
    key_end = i + len(key_match.group(0))
    return bib_start, key_start, key_match.group(1), key_end, len(cleaned)


def _normalize_bibitem_chunk(chunk: str) -> str | None:
    cleaned = _strip_diff_header_markup(chunk)
    found = _find_bibitem_key(cleaned)
    if found is None:
        return None

    bib_start, key_start, key, key_end, _ = found
    header = cleaned[bib_start:key_start].strip()
    header = re.sub(r"\s+", " ", header)
    rest = cleaned[key_end:]
    if rest and not rest.startswith(("\n", " ", "\t")):
        rest = "\n" + rest
    elif not rest:
        rest = "\n"
    return f"{header}{{{key}}}{rest}"


def normalize_bibitems(text: str) -> str:
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    i = 0

    while i < len(lines):
        line = lines[i]
        if r"\bibitem" not in line:
            match = KEY_LINE_RE.match(line.rstrip("\n"))
            recent = "".join(out[-3:])
            if match and r"\bibitem" in recent:
                ending = "\n" if line.endswith("\n") else ""
                out.append(f"{match.group(1)}{{{match.group(2)}}}{match.group(3)}{ending}")
            else:
                out.append(line)
            i += 1
            continue

        chunk_lines = [line]
        normalized = _normalize_bibitem_chunk("".join(chunk_lines))
        j = i + 1
        while normalized is None and j < len(lines) and j <= i + 5:
            chunk_lines.append(lines[j])
            normalized = _normalize_bibitem_chunk("".join(chunk_lines))
            j += 1

        if normalized is None:
            out.append(line)
            i += 1
            continue

        out.append(normalized)
        i = j

    return "".join(out)


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: normalize_bibitems.py MAIN_DIFF_TEX", file=sys.stderr)
        return 2

    diff_tex = Path(sys.argv[1])
    diff_tex.write_text(normalize_bibitems(diff_tex.read_text()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
