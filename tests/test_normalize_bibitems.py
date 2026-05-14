from __future__ import annotations

from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from normalize_bibitems import normalize_bibitems  # noqa: E402


class NormalizeBibitemsTest(unittest.TestCase):
    def test_modified_bibitem_label_keeps_key_parseable(self) -> None:
        source = r"""\DIFdelbegin %DIFDELCMD < \bibitem[Antoniades et~al\mbox{.}({[n.\,d.]})]%%%
\DIFdelend \DIFaddbegin \bibitem[Antoniades et~al\mbox{.}(2025)]\DIFaddend %
        {antoniades2025swe}
\bibfield{author}{Antonis Antoniades.}
"""

        tex = normalize_bibitems(source)

        self.assertIn(r"\bibitem[Antoniades et~al\mbox{.}(2025)]{antoniades2025swe}", tex)
        self.assertNotIn(r"\DIFaddend %", tex)
        self.assertIn(r"\bibfield{author}", tex)

    def test_added_bibitem_keeps_added_body_markup(self) -> None:
        source = r"""\DIFaddbegin \bibitem[Zhang et~al\mbox{.}(2025b)]%DIF >
        {zhang2025acfix}
\DIFadd{\bibfield{author}{Lyuye Zhang.} \bibinfo{year}{2025}}\natexlab{b}\DIFadd{.}
"""

        tex = normalize_bibitems(source)

        self.assertIn(r"\bibitem[Zhang et~al\mbox{.}(2025b)]{zhang2025acfix}", tex)
        self.assertIn(r"\DIFadd{\bibfield{author}{Lyuye Zhang.}", tex)

    def test_dif_wrapped_key_line_is_unwrapped(self) -> None:
        source = r"""\bibitem[Foo(2026)]
        {\DIFadd{foo2026}}
\bibfield{author}{Foo.}
"""

        tex = normalize_bibitems(source)

        self.assertIn(r"\bibitem[Foo(2026)]{foo2026}", tex)
        self.assertNotIn(r"\DIFadd{foo2026}", tex)

    def test_plain_bibitem_with_inline_body_preserves_body(self) -> None:
        source = r"""\bibitem[Foo(2026)]{foo2026} Author body.
\newblock Title.
"""

        tex = normalize_bibitems(source)

        self.assertIn(r"\bibitem[Foo(2026)]{foo2026}", tex)
        self.assertIn(" Author body.", tex)


if __name__ == "__main__":
    unittest.main()
