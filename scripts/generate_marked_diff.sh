#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Generate a reviewer-facing marked LaTeX diff PDF.

Usage:
  scripts/generate_marked_diff.sh --old OLD_DIR --new NEW_DIR [options]

Required:
  --old DIR          Pre-revision LaTeX source tree.
  --new DIR          Revised LaTeX source tree.

Options:
  --main FILE        Main TeX file relative to each tree. Default: main.tex
  --out DIR          Output directory. Default: marked_diff_output
  --tag TAG          Output tag. Default: revised git short hash or timestamp
  --replace-latex A=B
                    Exact post-latexdiff text replacement. Repeatable.
                    Useful for project-local ref rewrites in marked manuscripts.
  --allow-warnings   Do not fail on unresolved reference/citation warnings.
  -h, --help         Show this help.

Outputs:
  OUT_DIR/main_diff_TAG.pdf
  OUT_DIR/main_diff_TAG.tex
  OUT_DIR/work_TAG/table_diff_report.txt

Environment:
  LATEXDIFF_FLAGS    Extra latexdiff flags appended after the safe defaults.
USAGE
}

OLD_DIR=""
NEW_DIR=""
MAIN_TEX="main.tex"
OUT_DIR="marked_diff_output"
TAG=""
ALLOW_WARNINGS=0
LATEX_REPLACEMENTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --old)
      OLD_DIR="${2:-}"
      shift 2
      ;;
    --new)
      NEW_DIR="${2:-}"
      shift 2
      ;;
    --main)
      MAIN_TEX="${2:-}"
      shift 2
      ;;
    --out)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --replace-latex)
      LATEX_REPLACEMENTS+=("${2:-}")
      shift 2
      ;;
    --allow-warnings)
      ALLOW_WARNINGS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${OLD_DIR}" || -z "${NEW_DIR}" ]]; then
  echo "ERROR: --old and --new are required." >&2
  usage >&2
  exit 1
fi

if [[ ! -f "${OLD_DIR}/${MAIN_TEX}" ]]; then
  echo "ERROR: old main file not found: ${OLD_DIR}/${MAIN_TEX}" >&2
  exit 1
fi

if [[ ! -f "${NEW_DIR}/${MAIN_TEX}" ]]; then
  echo "ERROR: revised main file not found: ${NEW_DIR}/${MAIN_TEX}" >&2
  exit 1
fi

for cmd in latexdiff pdflatex bibtex rsync rg perl python3; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${cmd}" >&2
    exit 1
  fi
done

if [[ -z "${TAG}" ]]; then
  if git -C "${NEW_DIR}" rev-parse --short HEAD >/dev/null 2>&1; then
    TAG="$(git -C "${NEW_DIR}" rev-parse --short HEAD)"
  else
    TAG="$(date +%Y%m%d%H%M%S)"
  fi
fi

OLD_ABS="$(cd "${OLD_DIR}" && pwd)"
NEW_ABS="$(cd "${NEW_DIR}" && pwd)"
OUT_ABS="$(mkdir -p "${OUT_DIR}" && cd "${OUT_DIR}" && pwd)"
OLD_CLEAN="${OUT_ABS}/old_${TAG}"
WORK_DIR="${OUT_ABS}/work_${TAG}"
DIFF_TEX="${WORK_DIR}/main_diff.tex"

rm -rf "${OLD_CLEAN}" "${WORK_DIR}"
mkdir -p "${OLD_CLEAN}" "${WORK_DIR}"

COMMON_EXCLUDES=(
  --exclude='.git'
  --exclude='*.aux'
  --exclude='*.bbl'
  --exclude='*.blg'
  --exclude='*.fdb_latexmk'
  --exclude='*.fls'
  --exclude='*.log'
  --exclude='*.out'
  --exclude='*.synctex.gz'
  --exclude='main.pdf'
  --exclude='main_diff.pdf'
)

rsync -a --delete "${COMMON_EXCLUDES[@]}" "${OLD_ABS}/" "${OLD_CLEAN}/"
rsync -a --delete "${COMMON_EXCLUDES[@]}" "${NEW_ABS}/" "${WORK_DIR}/"

echo "Generating latexdiff..."
latexdiff \
  --flatten \
  --type=UNDERLINE \
  --subtype=SAFE \
  --floattype=FLOATSAFE \
  --graphics-markup=none \
  --disable-citation-markup \
  ${LATEXDIFF_FLAGS:-} \
  "${OLD_CLEAN}/${MAIN_TEX}" \
  "${NEW_ABS}/${MAIN_TEX}" \
  > "${DIFF_TEX}"

echo "Post-processing latexdiff output..."

# FLOATSAFE protects tables/figures, but it leaves whole added/deleted floats
# visually unmarked in many real papers. Keep float markup compile-safe while
# making whole-float replacements visible.
perl -0pi -e 's/\\providecommand\{\\DIFaddbeginFL\}\{\}/\\providecommand{\\DIFaddbeginFL}{\\color{blue}}/g;
              s/\\providecommand\{\\DIFaddendFL\}\{\}/\\providecommand{\\DIFaddendFL}{\\color{black}}/g;
              s/\\providecommand\{\\DIFdelbeginFL\}\{\}/\\providecommand{\\DIFdelbeginFL}{\\color{red}}/g;
              s/\\providecommand\{\\DIFdelendFL\}\{\}/\\providecommand{\\DIFdelendFL}{\\color{black}}/g;' "${DIFF_TEX}"

# Repair citation wrappers commonly produced when latexdiff meets natbib plus
# ulem/soul. Citation keys are metadata; the surrounding changed sentence still
# carries the visual addition/deletion mark.
perl -0pi -e 's/\\cite\s*\}\s*\\hspace\{0pt\}%DIFAUXCMD\s*\n\s*\}\{\\DIFadd\{([^{}]+)\}\}/\\cite{$1}/g;
              s/\\(cite|citep|citet)\s*\{\s*\\DIFadd\{([^{}]+)\}\s*\}/\\$1{$2}/g;
              s/\\(cite|citep|citet)\s+\\DIFadd\{([^{}]+)\}/\\$1{$2}/g;
              s/~\\cite\{([^{}]+)\}/~\\mbox{\\cite{$1}}/g;' "${DIFF_TEX}"

if [[ "${#LATEX_REPLACEMENTS[@]}" -gt 0 ]]; then
  python3 - "${DIFF_TEX}" "${LATEX_REPLACEMENTS[@]}" <<'PY'
from pathlib import Path
import sys

diff_tex = Path(sys.argv[1])
text = diff_tex.read_text()
for spec in sys.argv[2:]:
    if '=' not in spec:
        raise SystemExit(f'Invalid --replace-latex value, expected old=new: {spec}')
    old, new = spec.split('=', 1)
    text = text.replace(old, new)
diff_tex.write_text(text)
PY
fi

python3 - "${DIFF_TEX}" "${WORK_DIR}/whole_float_changes_report.txt" <<'PY'
from pathlib import Path
import re
import sys

diff_tex = Path(sys.argv[1])
report_path = Path(sys.argv[2])

lines = diff_tex.read_text().splitlines(keepends=True)
begin_re = re.compile(r'\\begin\{(table\*?|figure\*?)\}')
deleted_begin_re = re.compile(r'%DIFDELCMD < \\begin\{(table\*?|figure\*?)\}')

def kind_for_env(env: str) -> str:
    return 'table' if env.startswith('table') else 'figure'

def added_marker(env: str) -> str:
    return f'\\par\\noindent\\DIFaddFL{{\\textbf{{[Added {kind_for_env(env)}]}}}}\\par\\smallskip\n'

def deleted_marker(env: str) -> str:
    return f'\\par\\noindent\\DIFdelFL{{\\textbf{{[Deleted {kind_for_env(env)}]}}}}\\par\\smallskip\n'

# Make deleted floats visible even when latexdiff comments out the original
# float body. This adds a struck deletion label before the commented block.
out = []
marked = []
i = 0
while i < len(lines):
    if '\\DIFdelbeginFL' not in lines[i]:
        out.append(lines[i])
        i += 1
        continue

    j = i
    deleted_env = None
    while j < len(lines):
        match = deleted_begin_re.search(lines[j])
        if match:
            deleted_env = match.group(1)
        if '\\DIFdelendFL' in lines[j]:
            break
        j += 1

    if deleted_env:
        block_lines = lines[i:j + 1]
        already_marked = any('[Deleted ' in line for line in block_lines)
        out.append(lines[i])
        if not already_marked:
            out.append(deleted_marker(deleted_env))
            marked.append(f'{i + 1}: deleted {deleted_env}: visible deletion label inserted')
        out.extend(lines[i + 1:j + 1])
        i = j + 1
    else:
        out.append(lines[i])
        i += 1

lines = out
out = []
i = 0
while i < len(lines):
    begin_match = begin_re.search(lines[i])
    if not begin_match:
        out.append(lines[i])
        i += 1
        continue

    env = begin_match.group(1)
    end_re = re.compile(r'\\end\{' + re.escape(env) + r'\}')
    depth = 0
    j = i
    while j < len(lines):
        found_begin = begin_re.search(lines[j])
        if found_begin and found_begin.group(1) == env:
            depth += 1
        if end_re.search(lines[j]):
            depth -= 1
            if depth == 0:
                break
        j += 1

    if j >= len(lines):
        out.append(lines[i])
        i += 1
        continue

    block_lines = lines[i:j + 1]
    block = ''.join(block_lines)
    caption_is_added = re.search(r'\\caption(?:\[[^\]]*\])?\s*\{\\DIFaddFL\{', block) is not None
    already_whole_marked = (
        '\\DIFaddbeginFL' in lines[i]
        or (len(block_lines) > 1 and block_lines[1].lstrip().startswith('\\DIFaddbeginFL'))
        or '[Added ' in block
    )

    if caption_is_added and not already_whole_marked:
        block_lines = (
            block_lines[:1]
            + ['\\DIFaddbeginFL % scripted whole-float addition marker\n']
            + [added_marker(env)]
            + block_lines[1:-1]
            + ['\\DIFaddendFL % scripted whole-float addition marker\n']
            + block_lines[-1:]
        )
        caption_match = re.search(r'\\caption(?:\[[^\]]*\])?\s*\{\\DIFaddFL\{(.{0,120})', block, re.S)
        caption = caption_match.group(1).replace('\n', ' ').strip() if caption_match else '(caption unavailable)'
        marked.append(f'{i + 1}: added {env}: {caption}')

    out.extend(block_lines)
    i = j + 1

diff_tex.write_text(''.join(out))
report_path.write_text(
    'Whole float additions/deletions explicitly marked by post-processing\n'
    + '\n'.join(marked)
    + ('\n' if marked else 'None\n')
)
PY

{
  echo "Marked diff table/float coverage report"
  echo "Old source: ${OLD_ABS}"
  echo "Revised source: ${NEW_ABS}"
  echo "Main TeX: ${MAIN_TEX}"
  echo "Tag: ${TAG}"
  echo
  cat "${WORK_DIR}/whole_float_changes_report.txt"
  echo
  echo "Table-like environments found in marked diff:"
  rg -n '\\begin\{(tabular|tabularx|longtable)\}' "${DIFF_TEX}" || true
  echo
  echo "Float-level change markers found in marked diff:"
  rg -n '\\DIF(add|del)beginFL|\\DIF(add|del)FL' "${DIFF_TEX}" || true
} > "${WORK_DIR}/table_diff_report.txt"

echo "Compiling marked manuscript..."
(
  cd "${WORK_DIR}"
  export TEXMFHOME="${TEXMFHOME:-/tmp/empty-texmf}"
  export TEXMFVAR="${TEXMFVAR:-/tmp/texmf-var-clean}"
  pdflatex -interaction=nonstopmode -halt-on-error main_diff.tex >/tmp/marked_diff_pdflatex_1.log
  bibtex main_diff >/tmp/marked_diff_bibtex.log
  pdflatex -interaction=nonstopmode -halt-on-error main_diff.tex >/tmp/marked_diff_pdflatex_2.log
  pdflatex -interaction=nonstopmode -halt-on-error main_diff.tex >/tmp/marked_diff_pdflatex_3.log
)

if [[ "${ALLOW_WARNINGS}" -eq 0 ]] && rg -n 'Fatal error|Emergency stop|Undefined control sequence|There were undefined references|undefined citations|Reference `[^`]+'"'"' .*undefined|Citation `[^`]+` .*undefined' "${WORK_DIR}/main_diff.log" >/tmp/marked_diff_latex_errors.log; then
  cat /tmp/marked_diff_latex_errors.log >&2
  echo "ERROR: marked diff compiled with unresolved errors/warnings listed above." >&2
  exit 1
fi

cp "${WORK_DIR}/main_diff.pdf" "${OUT_ABS}/main_diff_${TAG}.pdf"
cp "${WORK_DIR}/main_diff.tex" "${OUT_ABS}/main_diff_${TAG}.tex"

echo "Done."
echo "PDF: ${OUT_ABS}/main_diff_${TAG}.pdf"
echo "TeX: ${OUT_ABS}/main_diff_${TAG}.tex"
echo "Table report: ${WORK_DIR}/table_diff_report.txt"
