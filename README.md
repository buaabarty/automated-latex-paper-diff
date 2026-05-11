# Automated LaTeX Paper Diff

Scripted generation of reviewer-facing marked manuscripts from two LaTeX source
trees. The workflow wraps `latexdiff`, fixes several common citation/table
failure cases, compiles the marked manuscript, and emits a table/float coverage
report so table changes are not missed during review.

## Why This Exists

For major revisions, a plain `latexdiff` run often fails or silently under-marks
large table changes. This script keeps the generation process reproducible:

- compares a pre-revision LaTeX tree with a revised tree;
- uses conservative `latexdiff` settings that compile with complex papers;
- keeps table and figure changes visible, including whole newly added tables;
- repairs common `natbib` citation wrappers produced by `latexdiff`;
- generates a report listing table environments and float-level diff markers;
- fails when the final LaTeX log contains fatal errors or unresolved references.

## Requirements

Install these command-line tools before running the script:

- `latexdiff`
- `pdflatex`
- `bibtex`
- `rsync`
- `ripgrep` (`rg`)
- `perl`
- `python3`

## Usage

```bash
scripts/generate_marked_diff.sh \
  --old /path/to/original-latex \
  --new /path/to/revised-latex \
  --main main.tex \
  --out marked_diff_output \
  --tag major_revision
```

Outputs:

```text
marked_diff_output/main_diff_major_revision.pdf
marked_diff_output/main_diff_major_revision.tex
marked_diff_output/work_major_revision/table_diff_report.txt
```

If a journal allows unresolved references in the marked manuscript but you still
want a PDF, pass:

```bash
scripts/generate_marked_diff.sh --old old --new revised --allow-warnings
```

For project-local fixes after substantial structural changes, use repeatable
exact LaTeX replacements. For example, if an old deleted sentence refers to a
figure label that no longer exists in the marked manuscript:

```bash
scripts/generate_marked_diff.sh \
  --old old \
  --new revised \
  --replace-latex 'Figure \ref{fig:old-scenario}=Figure~6'
```

## Table Marking

The script uses `latexdiff --floattype=FLOATSAFE` so complex tables remain
compilable. Because `FLOATSAFE` can leave newly added tables visually unmarked,
the post-processing step detects table/table* environments whose captions are
fully added and wraps the whole float with a scripted addition marker.

The generated `table_diff_report.txt` lists:

- whole table additions explicitly marked by the script;
- all `tabular`, `tabularx`, and `longtable` environments found in the marked
  manuscript;
- all float-level `DIFadd`/`DIFdel` markers found in the marked manuscript.

## Notes

The script intentionally avoids project-specific hard-coded labels. Use
`--replace-latex` for paper-specific reference rewrites.
