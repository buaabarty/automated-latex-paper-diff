# Changelog

All notable changes to this project are documented here.

## v0.1.2 - 2026-05-11

- Added underlined `[Added table]`/`[Added figure]` labels for whole newly added floats.
- Added struck `[Deleted table]`/`[Deleted figure]` labels for whole deleted floats whose bodies are commented out by `latexdiff`.
- Updated documentation to clarify that whole-float changes are not communicated by color alone.

## v0.1.1 - 2026-05-11

- Added GitHub Actions workflow for building and publishing Docker images to GitHub Container Registry.
- Documented prebuilt GHCR image usage and Docker tag policy.

## v0.1.0 - 2026-05-11

Initial public release.

- Added `scripts/generate_marked_diff.sh` for reproducible marked-manuscript generation.
- Added table-aware post-processing for whole newly added `table` and `table*` environments.
- Added citation cleanup for common `latexdiff` + `natbib` failures.
- Added `--replace-latex` for repeatable project-local reference rewrites.
- Added PDF compilation and unresolved reference/citation checks.
- Added `table_diff_report.txt` to audit table and float coverage.
- Added Docker support for a reusable TeX Live environment.
