#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

FLOAT_BEGIN_RE = re.compile(r"\\begin\{(table\*?|figure\*?)\}")
FLOAT_BEGIN_WITH_OPTION_RE = re.compile(r"(\\begin\{(table\*?|figure\*?)\})(?:\[[^\]\n]*\])?")
BEGIN_DOCUMENT_RE = re.compile(r"\\begin\{document\}")
COMMENTED_DELETED_FLOAT_BEGIN_RE = re.compile(r"%+DIFDELCMD <\s*\\begin\{(table\*?|figure\*?)\}")
COMMENTED_TABLE_BODY_RE = re.compile(r"%+DIFDELCMD <[^\n]*\\begin\{(?:tabular\*?|tabularx|longtable)\}")
COMMENTED_FIGURE_BODY_RE = re.compile(r"%+DIFDELCMD <[^\n]*\\includegraphics")
USEPACKAGE_RE = re.compile(r"\\usepackage(?:\[[^\]\n]*\])?\{([^}\n]+)\}")
ADDED_CAPTION_RE = re.compile(r"\\caption(?:\[[^\]]*\])?\s*\{\\DIFaddFL\{", re.S)
ADDED_CAPTION_TEXT_RE = re.compile(r"\\caption(?:\[[^\]]*\])?\s*\{\\DIFaddFL\{(.{0,120})", re.S)
DIF_MARKUP_COMMAND = r"\\DIF(?:add|del)(?:FL)?"
BOOKTABS_RANGE = r"([0-9]+\s*-\s*[0-9]+)"
CMIDRULE_SPLIT_OPTION_RE = re.compile(
    rf"\\cmidrule\s*{DIF_MARKUP_COMMAND}\{{\(([^{{}}\n]+)\)\}}\s*"
    rf"\{{\s*{DIF_MARKUP_COMMAND}\{{\s*{BOOKTABS_RANGE}\s*\}}\s*\}}"
)
CMIDRULE_WRAPPED_RANGE_RE = re.compile(
    rf"(\\cmidrule(?:\[[^\]\n]*\])?(?:\([^()\n]*\))?)\s*"
    rf"\{{\s*{DIF_MARKUP_COMMAND}\{{\s*{BOOKTABS_RANGE}\s*\}}\s*\}}"
)
CMIDRULE_DIRECT_RANGE_RE = re.compile(
    rf"\\cmidrule\s*{DIF_MARKUP_COMMAND}\{{\s*{BOOKTABS_RANGE}\s*\}}"
)


def kind_for_env(env: str) -> str:
    return "table" if env.startswith("table") else "figure"


def added_marker(env: str) -> str:
    return f"\\par\\noindent\\DIFaddFL{{\\textbf{{[Added {kind_for_env(env)}]}}}}\\par\\smallskip\n"


def deleted_marker(env: str) -> str:
    return f"\\par\\noindent\\DIFdelFL{{\\textbf{{[Deleted {kind_for_env(env)}]}}}}\\par\\smallskip\n"


def replaced_body_marker(env: str) -> str:
    return f"\\par\\noindent\\DIFdelFL{{\\textbf{{[Replaced {kind_for_env(env)} body]}}}}\\par\\smallskip\n"


def normalize_cmidrule_range(value: str) -> str:
    return re.sub(r"\s+", "", value)


def normalize_booktabs_cmidrules(lines: list[str], marked: list[str]) -> list[str]:
    text = "".join(lines)
    normalized = 0

    def replace_split_option(match: re.Match[str]) -> str:
        nonlocal normalized
        normalized += 1
        return f"\\cmidrule({match.group(1).strip()}){{{normalize_cmidrule_range(match.group(2))}}}"

    def replace_wrapped_range(match: re.Match[str]) -> str:
        nonlocal normalized
        normalized += 1
        return f"{match.group(1)}{{{normalize_cmidrule_range(match.group(2))}}}"

    def replace_direct_range(match: re.Match[str]) -> str:
        nonlocal normalized
        normalized += 1
        return f"\\cmidrule{{{normalize_cmidrule_range(match.group(1))}}}"

    text = CMIDRULE_SPLIT_OPTION_RE.sub(replace_split_option, text)
    text = CMIDRULE_WRAPPED_RANGE_RE.sub(replace_wrapped_range, text)
    text = CMIDRULE_DIRECT_RANGE_RE.sub(replace_direct_range, text)

    if normalized:
        marked.append(f"booktabs cmidrule: normalized {normalized} latexdiff-marked rule argument(s)")
    return text.splitlines(keepends=True)


def has_unescaped_comment_before(line: str, pos: int) -> bool:
    search_from = 0
    while True:
        percent = line.find("%", search_from, pos)
        if percent == -1:
            return False
        slash_count = 0
        index = percent - 1
        while index >= 0 and line[index] == "\\":
            slash_count += 1
            index -= 1
        if slash_count % 2 == 0:
            return True
        search_from = percent + 1


def active_search(pattern: re.Pattern[str], line: str) -> re.Match[str] | None:
    match = pattern.search(line)
    if not match:
        return None
    if has_unescaped_comment_before(line, match.start()):
        return None
    return match


def active_float_begin(line: str) -> re.Match[str] | None:
    return active_search(FLOAT_BEGIN_RE, line)


def active_begin_document(line: str) -> re.Match[str] | None:
    return active_search(BEGIN_DOCUMENT_RE, line)


def has_float_package(lines: list[str]) -> bool:
    for line in lines:
        match = active_search(USEPACKAGE_RE, line)
        if not match:
            continue
        packages = [package.strip() for package in match.group(1).split(",")]
        if "float" in packages:
            return True
    return False


def pin_active_float_placement(lines: list[str], marked: list[str]) -> list[str]:
    pinned = 0
    active_float_count = 0
    out: list[str] = []

    for line in lines:
        cursor = 0
        rewritten: list[str] = []
        for match in FLOAT_BEGIN_WITH_OPTION_RE.finditer(line):
            if has_unescaped_comment_before(line, match.start()):
                continue
            active_float_count += 1
            rewritten.append(line[cursor : match.start()])
            replacement = f"{match.group(1)}[H]"
            rewritten.append(replacement)
            if match.group(0) != replacement:
                pinned += 1
            cursor = match.end()
        if rewritten:
            rewritten.append(line[cursor:])
            out.append("".join(rewritten))
        else:
            out.append(line)

    if active_float_count and not has_float_package(out):
        for index, line in enumerate(out):
            if active_begin_document(line):
                out.insert(index, "\\usepackage{float} % scripted diff float placement\n")
                break

    if pinned:
        marked.append(f"float placement: pinned {pinned} active float(s) with [H]")

    return out


def find_active_float_end(lines: list[str], start: int, env: str) -> int | None:
    end_re = re.compile(r"\\end\{" + re.escape(env) + r"\}")
    depth = 0
    for index in range(start, len(lines)):
        found_begin = active_float_begin(lines[index])
        if found_begin and found_begin.group(1) == env:
            depth += 1
        if active_search(end_re, lines[index]):
            depth -= 1
            if depth == 0:
                return index
    return None


def has_commented_deleted_body(block: str, env: str) -> bool:
    if "\\DIFdelbeginFL" not in block:
        return False
    if kind_for_env(env) == "table":
        return COMMENTED_TABLE_BODY_RE.search(block) is not None
    return COMMENTED_FIGURE_BODY_RE.search(block) is not None


def clean_latexdiff_noise_inside_added_float(block_lines: list[str]) -> list[str]:
    text = "".join(block_lines)
    text = re.sub(
        r"\\DIFaddendFL\s*.*?\\DIFdelbegin(?:FL)?\s*.*?\\DIFdelend(?:FL)?\s*\\DIFaddbeginFL\s*",
        "",
        text,
        flags=re.S,
    )
    text = re.sub(r"\\DIFdelbegin(?:FL)?\s*.*?\\DIFdelend(?:FL)?\s*", "", text, flags=re.S)
    return text.splitlines(keepends=True)


def mark_commented_deleted_floats(lines: list[str], marked: list[str]) -> list[str]:
    out: list[str] = []
    i = 0
    while i < len(lines):
        if "\\DIFdelbeginFL" not in lines[i]:
            out.append(lines[i])
            i += 1
            continue

        j = i
        deleted_env = None
        while j < len(lines):
            match = COMMENTED_DELETED_FLOAT_BEGIN_RE.search(lines[j])
            if match:
                deleted_env = match.group(1)
            if "\\DIFdelendFL" in lines[j]:
                break
            j += 1

        if not deleted_env:
            out.append(lines[i])
            i += 1
            continue

        block_lines = lines[i : j + 1]
        already_marked = any("[Deleted " in line for line in block_lines)
        out.append(lines[i])
        if not already_marked:
            out.append(deleted_marker(deleted_env))
            marked.append(f"{i + 1}: deleted {deleted_env}: visible deletion label inserted")
        out.extend(lines[i + 1 : j + 1])
        i = j + 1

    return out


def mark_active_float_blocks(lines: list[str], marked: list[str]) -> list[str]:
    out: list[str] = []
    i = 0
    while i < len(lines):
        begin_match = active_float_begin(lines[i])
        if not begin_match:
            out.append(lines[i])
            i += 1
            continue

        env = begin_match.group(1)
        end = find_active_float_end(lines, i, env)
        if end is None:
            out.append(lines[i])
            i += 1
            continue

        block_lines = lines[i : end + 1]
        block = "".join(block_lines)

        if has_commented_deleted_body(block, env) and "[Deleted " not in block:
            block_lines = (
                block_lines[:1]
                + ["\\DIFdelbeginFL % scripted retained-float deletion marker\n"]
                + [replaced_body_marker(env)]
                + ["\\DIFdelendFL % scripted retained-float deletion marker\n"]
                + block_lines[1:]
            )
            marked.append(f"{i + 1}: replaced {env} body: visible replacement label inserted")
            block = "".join(block_lines)

        caption_is_added = ADDED_CAPTION_RE.search(block) is not None
        already_whole_marked = (
            "\\DIFaddbeginFL" in lines[i]
            or (len(block_lines) > 1 and block_lines[1].lstrip().startswith("\\DIFaddbeginFL"))
            or "[Added " in block
        )

        if caption_is_added and not already_whole_marked:
            block_lines = clean_latexdiff_noise_inside_added_float(block_lines)
            block_lines = (
                block_lines[:1]
                + ["\\DIFaddbeginFL % scripted whole-float addition marker\n"]
                + [added_marker(env)]
                + block_lines[1:-1]
                + ["\\DIFaddendFL % scripted whole-float addition marker\n"]
                + block_lines[-1:]
            )
            caption_match = ADDED_CAPTION_TEXT_RE.search(block)
            caption = caption_match.group(1).replace("\n", " ").strip() if caption_match else "(caption unavailable)"
            marked.append(f"{i + 1}: added {env}: {caption}")

        out.extend(block_lines)
        i = end + 1

    return out


def postprocess(diff_tex: Path, report_path: Path) -> None:
    lines = diff_tex.read_text().splitlines(keepends=True)
    marked: list[str] = []

    lines = normalize_booktabs_cmidrules(lines, marked)
    lines = pin_active_float_placement(lines, marked)
    lines = mark_commented_deleted_floats(lines, marked)
    lines = mark_active_float_blocks(lines, marked)

    diff_tex.write_text("".join(lines))
    report_path.write_text(
        "Whole float and retained-body additions/deletions explicitly marked by post-processing\n"
        + "\n".join(marked)
        + ("\n" if marked else "None\n")
    )


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("Usage: postprocess_marked_diff.py DIFF_TEX REPORT_PATH", file=sys.stderr)
        return 2
    postprocess(Path(argv[1]), Path(argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
