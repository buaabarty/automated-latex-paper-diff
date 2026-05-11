# Automated LaTeX Paper Diff

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25.svg)
![LaTeX](https://img.shields.io/badge/LaTeX-latexdiff-008080.svg)
![Docker](https://img.shields.io/badge/Docker-supported-2496ED.svg)
[![Docker Image](https://github.com/buaabarty/automated-latex-paper-diff/actions/workflows/docker-image.yml/badge.svg)](https://github.com/buaabarty/automated-latex-paper-diff/actions/workflows/docker-image.yml)

Generate reviewer-facing marked manuscripts from two LaTeX source trees with a
reproducible, table-aware `latexdiff` workflow.

Plain `latexdiff` is excellent for simple papers, but major revisions often
break it: citations can become invalid, large tables can compile without visible
change marks, and float-level replacements can disappear into unhelpful markup.
This project wraps `latexdiff` with safe defaults, practical post-processing,
PDF compilation, and an audit report that tells you whether table and float
changes were actually marked.

## Highlights

- Compares a pre-revision LaTeX tree against a revised tree.
- Produces a marked PDF, marked `.tex`, and a table/float coverage report.
- Uses conservative `latexdiff` settings that work better on real papers.
- Marks whole newly added/deleted tables and figures with visible labels, not
  only color changes.
- Repairs common `natbib`/`ulem` citation wrappers produced by `latexdiff`.
- Supports repeatable project-local LaTeX replacements for obsolete references.
- Provides a Docker workflow so users do not need to install TeX Live locally.

## Quick Start With Docker

Use the prebuilt image from GitHub Container Registry:

```bash
docker pull ghcr.io/buaabarty/automated-latex-paper-diff:latest
```

Run it from a directory that contains two LaTeX source trees, for example
`paper-original/` and `paper-revised/`:

```bash
docker run --rm \
  -v "$PWD":/work \
  ghcr.io/buaabarty/automated-latex-paper-diff:latest \
  --old /work/paper-original \
  --new /work/paper-revised \
  --main main.tex \
  --out /work/marked_diff_output \
  --tag major_revision
```

Alternatively, build the image locally:

```bash
git clone https://github.com/buaabarty/automated-latex-paper-diff.git
cd automated-latex-paper-diff
docker build -t automated-latex-paper-diff:latest .
```

Then run the local image:

```bash
docker run --rm \
  -v "$PWD":/work \
  automated-latex-paper-diff:latest \
  --old /work/paper-original \
  --new /work/paper-revised \
  --main main.tex \
  --out /work/marked_diff_output \
  --tag major_revision
```

Outputs:

```text
marked_diff_output/main_diff_major_revision.pdf
marked_diff_output/main_diff_major_revision.tex
marked_diff_output/work_major_revision/table_diff_report.txt
```

The Docker image intentionally includes a broad TeX Live installation because
marked manuscripts often use journal classes, custom fonts, and packages from
the original paper. If your paper uses rare system fonts or external tools,
extend the provided `Dockerfile`.

## Local Installation

Install these commands on your machine:

- `latexdiff`
- `pdflatex`
- `bibtex`
- `rsync`
- `ripgrep` (`rg`)
- `perl`
- `python3`

Then run:

```bash
scripts/generate_marked_diff.sh \
  --old /path/to/original-latex \
  --new /path/to/revised-latex \
  --main main.tex \
  --out marked_diff_output \
  --tag major_revision
```

## Handling Structural Rewrites

Major revisions often replace a figure with a table, split a section, or remove
an old label. If the deleted old text still contains a reference that no longer
exists in the marked manuscript, use a repeatable exact replacement:

```bash
scripts/generate_marked_diff.sh \
  --old paper-original \
  --new paper-revised \
  --replace-latex 'Figure \ref{fig:old-scenario}=Figure~6'
```

You can pass `--replace-latex` multiple times. The replacement is applied after
`latexdiff` and before PDF compilation.

## Table-Aware Marking

The script runs `latexdiff` with `--floattype=FLOATSAFE` so complex tables and
figures are more likely to compile. A side effect of `FLOATSAFE` is that fully
new tables can be present in the PDF without visually obvious addition markup.

After `latexdiff` runs, the script overrides all generated `DIFadd`, `DIFdel`,
`DIFaddFL`, and `DIFdelFL` macros so additions are underlined and deletions are
struck through everywhere, including table cells and captions. This override is
applied even if `LATEXDIFF_FLAGS` includes another `--type` value.

To avoid that failure mode, the script detects `table`, `table*`, `figure`, and
`figure*` environments whose captions are fully added and wraps the whole float
in a scripted addition marker. It also inserts a visible deletion label when a
deleted float body is commented out by `latexdiff`. These labels use the same
underlined/struck diff commands as the rest of the marked manuscript, so changes
are not communicated by color alone. The generated `table_diff_report.txt`
lists:

- whole float additions/deletions explicitly marked by post-processing;
- all `tabular`, `tabularx`, and `longtable` environments in the marked file;
- all float-level `DIFadd`/`DIFdel` markers in the marked file.

This report is useful before submission because it makes table coverage
checkable rather than relying on visual inspection alone.

## Command Reference

```text
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
  --allow-warnings   Do not fail on unresolved reference/citation warnings.
  -h, --help         Show help.

Environment:
  LATEXDIFF_FLAGS    Extra latexdiff flags appended after the safe defaults.
```

## Make Targets

```bash
make smoke         # shell syntax check
make docker-build  # build local Docker image
```

## Published Images

The Docker image is published by GitHub Actions to:

```text
ghcr.io/buaabarty/automated-latex-paper-diff
```

Tags:

- `latest`: latest successful build from `main`;
- `vX.Y.Z`: release tags;
- `sha-<commit>`: commit-specific image tags.

## Known Limits

- The tool assumes both source trees can compile with `pdflatex`/`bibtex`.
- It does not infer semantic equivalence between rewritten tables; it marks
  what `latexdiff` and the scripted post-processing can identify.
- Very complex custom macros may still require project-local `--replace-latex`
  rules or minor manual cleanup in the generated diff `.tex`.
- The Docker image is convenience-oriented, not minimal.

## Contributing

Bug reports and small, reproducible examples are welcome. The most useful issue
contains:

- a minimal old/new LaTeX pair;
- the command you ran;
- the LaTeX error or the table/float marking problem you observed;
- the generated `table_diff_report.txt`, if available.

## License

MIT. See [LICENSE](LICENSE).
