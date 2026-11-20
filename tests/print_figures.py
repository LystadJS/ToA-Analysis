"""Check the published country, coverage and evidence figures using Poppler."""
import csv
from pathlib import Path
import re
import struct
import subprocess


def poppler(tool, *args):
    return subprocess.check_output([tool, *args], text=True)


def check_pdf(path, pages):
    info = poppler("pdfinfo", path)
    assert re.search(rf"^Pages:\s+{pages}$", info, re.MULTILINE), path
    fonts = poppler("pdffonts", path).splitlines()[2:]
    wanted = {"AtkinsonHyperlegibleNext", "EBGaramond", "JetBrainsMono"}
    found = set()
    for line in fonts:
        font = line.split()[0].split("+")[-1].split("-")[0]
        assert line.split()[-5:-2] == ["yes", "yes", "yes"], (path, line)
        found.add(font)
    assert found == wanted, (path, found)
    return poppler("pdftotext", "-layout", path, "-")


def main():
    artifacts = Path("artifacts")
    folders = sorted((artifacts / "countries").glob("???"))
    assert len(folders) == 250
    coverage = check_pdf(artifacts / "coverage/Country-year-coverage.pdf", 8)
    for folder in folders:
        assert re.search(r"·\s+" + folder.name + r"\b", coverage), folder
        text = check_pdf(folder / "country.pdf", 1)
        with (folder / "annual_finance.csv").open() as f:
            series = {r["series"] for r in csv.DictReader(f) if r["value"]}
        with (folder / "trade_context.csv").open() as f:
            has_context = next(csv.DictReader(f), None) is not None
        assert "National logistics lead time" in text, folder
        assert text.count("No observation in these releases") == 5 - len(series) - has_context, folder
        if not series and not has_context:
            assert "0.025" not in text, folder
    evidence = check_pdf(artifacts / "philippines_registration.pdf", 1)
    assert all(v in evidence for v in ("Manual books", "Loose-leaf books", "Authority to print", "11.67", "53"))
    with (artifacts / "coverage/US-spending-coverage.png").open("rb") as image:
        assert image.read(16).startswith(b"\x89PNG\r\n\x1a\n")
        assert struct.unpack(">II", image.read(8)) == (1500, 900)
    print("All 250 country PDFs, the eight-page coverage PDF and the Philippines figure contain "
          "the three embedded, searchable fonts. All country codes and empty panels verified. "
          "The spending revisions PNG is 1500 × 900.")


if __name__ == "__main__":
    main()
