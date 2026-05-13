#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSTPROCESS_SCRIPT="${SCRIPT_DIR}/postprocess_marked_diff.py"

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

print_log_excerpt() {
  local file="$1"
  local label="$2"

  if [[ -s "${file}" ]]; then
    echo "--- ${label}: ${file} ---" >&2
    tail -80 "${file}" >&2
  fi
}

run_pdflatex_or_show_log() {
  local log_file="$1"
  local produced_log="$2"
  shift 2

  local code=0
  pdflatex -interaction=nonstopmode -halt-on-error "$@" >"${log_file}" || code=$?
  if [[ "${code}" -eq 0 ]]; then
    return 0
  fi

  echo "ERROR: pdflatex $* failed with exit code ${code}." >&2
  print_log_excerpt "${log_file}" "pdflatex stdout"
  print_log_excerpt "${produced_log}" "pdflatex log"
  return "${code}"
}

run_bibtex_with_optional_warnings() {
  local job="$1"
  local log_file="$2"
  local bbl_file="${job}.bbl"
  local blg_file="${job}.blg"

  local code=0
  bibtex "${job}" >"${log_file}" || code=$?
  if [[ "${code}" -eq 0 ]]; then
    return 0
  fi

  if [[ "${ALLOW_WARNINGS}" -eq 1 && -s "${bbl_file}" ]]; then
    echo "WARNING: bibtex ${job} exited with ${code}, but ${bbl_file} was generated; continuing because --allow-warnings is set." >&2
    print_log_excerpt "${log_file}" "bibtex stdout"
    print_log_excerpt "${blg_file}" "bibtex log"
    return 0
  fi

  echo "ERROR: bibtex ${job} failed with exit code ${code}." >&2
  print_log_excerpt "${log_file}" "bibtex stdout"
  print_log_excerpt "${blg_file}" "bibtex log"
  return "${code}"
}

prepare_bibliography_diff_source() {
  local tree="$1"
  local label="$2"
  local job="__latexdiff_${label}_refs"

  if ! rg -q --glob '*.tex' '\\bibliography\s*\{' "${tree}"; then
    return 0
  fi

  echo "Preparing ${label} bibliography for reference diff..."
  (
    cd "${tree}"
    rm -f "${job}.aux" "${job}.bbl" "${job}.blg" "${job}.log" "${job}.out" "${job}.pdf"
    run_pdflatex_or_show_log "/tmp/${job}_pdflatex.log" "${job}.log" -jobname="${job}" "${MAIN_TEX}"
    if ! rg -q '\\bibdata\{' "${job}.aux"; then
      echo "ERROR: ${label} source contains \\bibliography but ${job}.aux has no BibTeX data." >&2
      exit 1
    fi
    run_bibtex_with_optional_warnings "${job}" "/tmp/${job}_bibtex.log"
  )

  if [[ ! -s "${tree}/${job}.bbl" ]]; then
    echo "ERROR: failed to generate ${label} bibliography file for reference diff: ${tree}/${job}.bbl" >&2
    print_log_excerpt "/tmp/${job}_pdflatex.log" "${label} bibliography pdflatex log"
    print_log_excerpt "/tmp/${job}_bibtex.log" "${label} bibliography bibtex stdout"
    print_log_excerpt "${tree}/${job}.blg" "${label} bibliography bibtex log"
    exit 1
  fi

  python3 - "${tree}" "${tree}/${job}.bbl" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
bbl_path = Path(sys.argv[2])
bbl = bbl_path.read_text()
replacement = (
    '\n%DIF INLINE BIBLIOGRAPHY BEGIN\n'
    + bbl.rstrip()
    + '\n%DIF INLINE BIBLIOGRAPHY END\n'
)
pattern = re.compile(r'\\bibliography\s*\{[^{}]*\}')
replaced = 0

for tex_path in root.rglob('*.tex'):
    text = tex_path.read_text()

    def repl(match: re.Match[str]) -> str:
        global replaced
        line_start = text.rfind('\n', 0, match.start()) + 1
        prefix = text[line_start:match.start()]
        percent = prefix.find('%')
        if percent != -1 and (percent == 0 or prefix[percent - 1] != '\\'):
            return match.group(0)
        replaced += 1
        return replacement

    new_text = pattern.sub(repl, text)
    if new_text != text:
        tex_path.write_text(new_text)

if replaced == 0:
    raise SystemExit('No active \\bibliography command was replaced with the generated .bbl content.')
PY

  rm -f "${tree}/${job}.aux" "${tree}/${job}.bbl" "${tree}/${job}.blg" "${tree}/${job}.log" "${tree}/${job}.out" "${tree}/${job}.pdf"
}

prepare_bibliography_diff_source "${OLD_CLEAN}" "old"
prepare_bibliography_diff_source "${WORK_DIR}" "new"

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
  "${WORK_DIR}/${MAIN_TEX}" \
  > "${DIFF_TEX}"

echo "Post-processing latexdiff output..."

if [[ ! -f "${POSTPROCESS_SCRIPT}" ]]; then
  echo "ERROR: post-processing helper not found: ${POSTPROCESS_SCRIPT}" >&2
  exit 1
fi

python3 - "${DIFF_TEX}" <<'PY'
from pathlib import Path
import sys

diff_tex = Path(sys.argv[1])
text = diff_tex.read_text()
marker = '%DIF END PREAMBLE EXTENSION ADDED BY LATEXDIFF'
override = r'''
%DIF REVIEW MARKUP OVERRIDE %DIF PREAMBLE
\RequirePackage[normalem]{ulem} %DIF PREAMBLE
\providecommand{\DIFseadd}[1]{{\protect\color{blue}\uline{#1}}} %DIF PREAMBLE
\providecommand{\DIFsedel}[1]{{\protect\color{red}\sout{#1}}} %DIF PREAMBLE
\providecommand{\DIFaddbeginFL}{} %DIF PREAMBLE
\providecommand{\DIFaddendFL}{} %DIF PREAMBLE
\providecommand{\DIFdelbeginFL}{} %DIF PREAMBLE
\providecommand{\DIFdelendFL}{} %DIF PREAMBLE
\renewcommand{\DIFadd}[1]{\DIFseadd{#1}} %DIF PREAMBLE
\renewcommand{\DIFdel}[1]{\DIFsedel{#1}} %DIF PREAMBLE
\renewcommand{\DIFaddFL}[1]{\DIFseadd{#1}} %DIF PREAMBLE
\renewcommand{\DIFdelFL}[1]{\DIFsedel{#1}} %DIF PREAMBLE
\renewcommand{\DIFaddbeginFL}{} %DIF PREAMBLE
\renewcommand{\DIFaddendFL}{} %DIF PREAMBLE
\renewcommand{\DIFdelbeginFL}{} %DIF PREAMBLE
\renewcommand{\DIFdelendFL}{} %DIF PREAMBLE
%DIF END REVIEW MARKUP OVERRIDE %DIF PREAMBLE
'''.strip()
if override not in text:
    if marker in text:
        text = text.replace(marker, override + '\n' + marker, 1)
    else:
        text = override + '\n' + text
diff_tex.write_text(text)
PY

# Repair citation wrappers commonly produced when latexdiff meets natbib plus
# ulem/soul. Citation keys are metadata; the surrounding changed sentence still
# carries the visual addition/deletion mark.
perl -0pi -e 's/\\cite\s*\}\s*\\hspace\{0pt\}%DIFAUXCMD\s*\n\s*\}\{\\DIFadd\{([^{}]+)\}\}/\\cite{$1}/g;
              s/\\(cite|citep|citet)\s*\{\s*\\DIFadd\{([^{}]+)\}\s*\}/\\$1{$2}/g;
              s/\\(cite|citep|citet)\s+\\DIFadd\{([^{}]+)\}/\\$1{$2}/g;
              s/~\\cite\{([^{}]+)\}/~\\mbox{\\cite{$1}}/g;' "${DIFF_TEX}"

python3 - "${DIFF_TEX}" <<'PY'
from pathlib import Path
import re
import sys

diff_tex = Path(sys.argv[1])
lines = diff_tex.read_text().splitlines(keepends=True)
key_line = re.compile(r'^(\s*)\{\\DIF(?:add|del)\{([A-Za-z0-9_.:/-]+)\}\}(\s*)$')

out = []
for line in lines:
    match = key_line.match(line.rstrip('\n'))
    recent = ''.join(out[-3:])
    if match and '\\bibitem' in recent:
        ending = '\n' if line.endswith('\n') else ''
        out.append(f'{match.group(1)}{{{match.group(2)}}}{match.group(3)}{ending}')
    else:
        out.append(line)

diff_tex.write_text(''.join(out))
PY

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

python3 "${POSTPROCESS_SCRIPT}" "${DIFF_TEX}" "${WORK_DIR}/whole_float_changes_report.txt"

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
  run_pdflatex_or_show_log /tmp/marked_diff_pdflatex_1.log main_diff.log main_diff.tex
  if rg -q '\\bibdata\{' main_diff.aux; then
    run_bibtex_with_optional_warnings main_diff /tmp/marked_diff_bibtex.log
  else
    : > /tmp/marked_diff_bibtex.log
  fi
  run_pdflatex_or_show_log /tmp/marked_diff_pdflatex_2.log main_diff.log main_diff.tex
  run_pdflatex_or_show_log /tmp/marked_diff_pdflatex_3.log main_diff.log main_diff.tex
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
