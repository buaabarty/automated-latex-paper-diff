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
    def test_marks_retained_table_body_replacement_without_claiming_whole_table_deleted(self) -> None:
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

        self.assertIn(r"\DIFdelFL{\textbf{[Replaced table body]}}", tex)
        self.assertNotIn(r"\DIFdelFL{\textbf{[Deleted table]}}", tex)
        self.assertIn("replaced table* body: visible replacement label inserted", report)

    def test_removes_orphan_deleted_text_inside_whole_added_float(self) -> None:
        tex, report = run_postprocess(
            r"""
\begin{table}[t]
\caption{\DIFaddFL{pass@1/pass@5/pass@10 (\%) of the reduce-first baseline.}}
\begin{tabular}{lccc}
\toprule
\textbf{\DIFaddFL{Prompt setting}} & \textbf{\DIFaddFL{pass@1}} & \textbf{\DIFaddFL{pass@5}} & \textbf{\DIFaddFL{pass@10}} \\
\midrule
\DIFaddFL{Origin Test }& \DIFaddFL{4.1 }& \DIFaddFL{13.1 }& \DIFaddFL{19.0 }\\
\DIFaddendFL \tool \DIFdelbeginFL \DIFdelFL{; the gap at pass@10 is also significant.}\DIFdelendFL \DIFaddbeginFL \DIFaddFL{Reduced Test }& \textbf{\DIFaddFL{6.3}} & \textbf{\DIFaddFL{17.9}} & \textbf{\DIFaddFL{25.5}} \\
\bottomrule
\end{tabular}
\end{table}
"""
        )

        self.assertIn(r"\DIFaddFL{\textbf{[Added table]}}", tex)
        self.assertIn(r"\DIFaddFL{Reduced Test }&", tex)
        self.assertNotIn(r"\tool \DIFdelbeginFL", tex)
        self.assertNotIn("the gap at pass@10 is also significant", tex)
        self.assertIn("added table:", report)

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

    def test_normalizes_latexdiff_markup_inside_booktabs_cmidrule(self) -> None:
        tex, report = run_postprocess(
            r"""
\begin{table}[t]
\begin{tabular}{@{}l ccc ccc@{}}
\toprule
Metric & \multicolumn{3}{c}{A} & \multicolumn{3}{c}{B}\\
\cmidrule\DIFaddFL{(lr)}{\DIFaddFL{2-4}}\cmidrule\DIFaddFL{(lr)}{\DIFaddFL{5-7}}
 & One & Two & Three & Four & Five & Six\\
\midrule
Value & 1 & 2 & 3 & 4 & 5 & 6\\
\bottomrule
\end{tabular}
\end{table}
"""
        )

        self.assertIn(r"\cmidrule(lr){2-4}\cmidrule(lr){5-7}", tex)
        self.assertNotIn(r"\cmidrule\DIFaddFL", tex)
        self.assertIn("booktabs cmidrule: normalized 2", report)

    def test_normalizes_wrapped_booktabs_cmidrule_range(self) -> None:
        tex, report = run_postprocess(
            r"""
\begin{tabular}{lll}
\cmidrule(lr){\DIFaddFL{ 2 - 3 }}
\cmidrule\DIFdelFL{4-5}
\end{tabular}
"""
        )

        self.assertIn(r"\cmidrule(lr){2-3}", tex)
        self.assertIn(r"\cmidrule{4-5}", tex)
        self.assertIn("booktabs cmidrule: normalized 2", report)


if __name__ == "__main__":
    unittest.main()
