from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
POSTPROCESS = ROOT / "scripts" / "postprocess_marked_diff.py"


def run_postprocess(source: str) -> tuple[str, str]:
    with tempfile.TemporaryDirectory() as tmp:
        diff_tex = Path(tmp) / "main_diff.tex"
        report = Path(tmp) / "whole_float_changes_report.txt"
        diff_tex.write_text(source)

        subprocess.run([sys.executable, str(POSTPROCESS), str(diff_tex), str(report)], check=True)

        return diff_tex.read_text(), report.read_text()


class PostprocessMarkedDiffTest(unittest.TestCase):
    def test_marks_retained_table_with_commented_deleted_body(self) -> None:
        tex, report = run_postprocess(
            r"""
\begin{table*}[t]
\DIFdelbeginFL %DIFDELCMD < \small
%DIFDELCMD < \resizebox{\textwidth}{!}{%
%DIFDELCMD < \begin{tabular}{ll}
%DIFDELCMD < Old & Body \\
%DIFDELCMD < \end{tabular}}
\DIFdelendFL \DIFaddbeginFL \scriptsize
\DIFaddendFL \caption{\DIFdelbeginFL \DIFdelFL{Old caption}\DIFdelendFL \DIFaddbeginFL \DIFaddFL{New caption}\DIFaddendFL}
\DIFaddbeginFL \resizebox{\textwidth}{!}{%
\begin{tabular}{ll}
New & Body \\
\end{tabular}}
\DIFaddendFL
\end{table*}
"""
        )

        self.assertIn(r"\DIFdelFL{\textbf{[Deleted table]}}", tex)
        self.assertIn("deleted table* body: visible deletion label inserted", report)

    def test_does_not_mark_minor_cell_deletion(self) -> None:
        tex, report = run_postprocess(
            r"""
\begin{table}[h]
\caption{Still the same table}
\begin{tabular}{ll}
Name & \DIFdelbeginFL \DIFdelFL{old}\DIFdelendFL \DIFaddbeginFL \DIFaddFL{new}\DIFaddendFL \\
\end{tabular}
\end{table}
"""
        )

        self.assertNotIn("[Deleted table]", tex)
        self.assertTrue(report.endswith("None\n"))

    def test_preserves_whole_deleted_float_marker(self) -> None:
        tex, report = run_postprocess(
            r"""
\DIFdelbeginFL %DIFDELCMD < \begin{table}[h]
%DIFDELCMD < \caption{Old table}
%DIFDELCMD < \begin{tabular}{ll}
%DIFDELCMD < Old & Body \\
%DIFDELCMD < \end{tabular}
%DIFDELCMD < \end{table}
\DIFdelendFL
"""
        )

        self.assertIn(r"\DIFdelFL{\textbf{[Deleted table]}}", tex)
        self.assertIn("deleted table: visible deletion label inserted", report)

    def test_preserves_whole_added_float_marker(self) -> None:
        tex, report = run_postprocess(
            r"""
\begin{table}[h]
\caption{\DIFaddFL{New table}}
\begin{tabular}{ll}
New & Body \\
\end{tabular}
\end{table}
"""
        )

        self.assertIn(r"\DIFaddFL{\textbf{[Added table]}}", tex)
        self.assertIn("added table:", report)


if __name__ == "__main__":
    unittest.main()
