from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
GENERATE_SCRIPT = ROOT / "scripts" / "generate_marked_diff.sh"


class GenerateMarkedDiffDefaultsTest(unittest.TestCase):
    def test_find_summary_boxes_are_registered_as_text_commands(self) -> None:
        script = GENERATE_SCRIPT.read_text()
        self.assertIn("--append-textcmd=find", script)

    @unittest.skipUnless(shutil.which("latexdiff"), "latexdiff is not installed")
    def test_latexdiff_marks_words_inside_find_boxes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            old_tex = tmp_path / "old.tex"
            new_tex = tmp_path / "new.tex"
            old_tex.write_text(
                r"""\documentclass{article}
\newcommand{\find}[1]{\fbox{#1}}
\begin{document}
\find{{\bf [RQ-5]} \textbf{[Findings]:} old result. \textbf{[Insights]:} old mechanism.}
\end{document}
"""
            )
            new_tex.write_text(
                r"""\documentclass{article}
\newcommand{\find}[1]{\fbox{#1}}
\begin{document}
\find{{\bf [RQ-5]} \textbf{[Findings]:} new result. \textbf{[Insights]:} new mechanism.}
\end{document}
"""
            )

            result = subprocess.run(
                [
                    "latexdiff",
                    "--type=UNDERLINE",
                    "--subtype=SAFE",
                    "--disable-citation-markup",
                    "--append-textcmd=find",
                    str(old_tex),
                    str(new_tex),
                ],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
            )

        self.assertIn(r"\find{{\bf [RQ-5]}", result.stdout)
        self.assertIn(r"\DIFdel{old }", result.stdout)
        self.assertIn(r"\DIFadd{new }", result.stdout)
        self.assertNotIn(r"\DIFdel{\find", result.stdout)
        self.assertNotIn(r"\DIFadd{\find", result.stdout)


if __name__ == "__main__":
    unittest.main()
