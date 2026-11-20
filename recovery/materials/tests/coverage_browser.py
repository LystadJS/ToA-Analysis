"""Verify the standalone audit's rendered figures, filters and downloaded cells offline."""
import csv
import io
import os
from pathlib import Path
import shutil
import sys
from playwright.sync_api import sync_playwright, expect


def run(path):
    html = path.read_text()
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=os.getenv("CHROMIUM_PATH") or shutil.which("chromium"))
        context = browser.new_context(offline=True, accept_downloads=True, viewport={"width": 1440, "height": 990})
        page = context.new_page()
        failures, requests = [], []
        page.on("pageerror", lambda error: failures.append(str(error)))
        page.on("request", lambda req: requests.append(req.url))
        page.set_content(html)
        el = page.locator

        def select_cell(code, year):
            el(f'button.cell[data-country="{code}"][data-year="{year}"]').click()

        def series(source_label):
            el("#series").select_option(label=source_label)

        def export():
            with page.expect_download() as info:
                el("#export").click()
            return list(csv.DictReader(io.StringIO(info.value.path().read_text())))

        expect(el("#pageInfo")).to_have_text("1–16 of 250 jurisdictions")
        expect(el("#legend")).to_contain_text("Sector file only")
        assert el("button.cell").count() == 160
        select_cell("ISR", "2024")
        expect(el("#detail")).to_contain_text("$6,818,569,348")
        expect(el("#detail")).to_contain_text("$900,001")
        el("#next").click()
        expect(el("#pageInfo")).to_contain_text("17–32")
        el("#query").fill("bahrain")
        select_cell("BHR", "2024")
        expect(el("#detail")).to_contain_text("Sector file only")
        expect(el("#detail")).to_contain_text("$23,521,275")
        rows = export()
        assert len(rows) == 10 and {r["iso3"] for r in rows} == {"BHR"}
        row = next(r for r in rows if r["fiscal_year"] == "2024")
        assert row["database_usd"] == "" and row["paired_difference_usd"] == ""
        el("#query").fill("no-country-found")
        expect(el("#export")).to_be_disabled()
        el("#query").fill("")
        el("#observe").click()
        expect(el("#series")).to_have_value("3")
        el("#query").fill("KEN")
        series("AidData GCDF · disbursement")
        select_cell("KEN", "2020")
        expect(el("#detail")).to_contain_text("No country row")
        el("#to").select_option("2025")
        select_cell("KEN", "2025")
        expect(el("#detail")).to_contain_text("No rows in series that year")
        el("#donor").select_option("USA")
        el("#kind").select_option("Results")
        series("MCC · Outcome")
        el("#query").fill("Philippines")
        select_cell("PHL", "")
        expect(el("#detail")).to_contain_text("Undated")
        expect(el("#detail")).to_contain_text("Numeric values")
        assert any(r["year"] == "" and int(r["records"]) > 0 for r in export())
        el("#kind").select_option("Funding")
        series("World Bank PPI · sponsor equity commitment")
        el("#query").fill("BRA")
        el("#from").select_option("1999")
        cells = el("#matrix button.partial, #matrix button.missing")
        assert cells.count() > 0
        cells.first.click()
        expect(el("#detail")).to_contain_text("Summary-eligible rows")
        el("#donor").select_option("Shared")
        expect(el("#kind")).to_have_value("Context")
        el("#series").select_option(label="Import · Survey lead time")
        el("#query").fill("Honduras")
        select_cell("HND", "2007")
        expect(el("#detail")).to_contain_text("All rows have numeric values")
        assert el("#nationalTable tbody tr").count() == 6
        expect(el("#greenbook")).to_contain_text("$25,293,693,021")
        expect(el("#kenyaLinks a")).to_have_count(3)

        page.set_viewport_size({"width": 390, "height": 844})
        el("#observe").click()
        expect(el("#matrix tbody tr")).to_have_count(1)
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        assert requests == [] and failures == [], (requests, failures)
        context.close()
        browser.close()
    print("Offline Chromium checks passed for heatmap cells, reports, years, missingness, country search, "
          "all four record types, pagination, CSV export and mobile layout.")


if __name__ == "__main__":
    run(Path(sys.argv[1] if len(sys.argv) > 1 else "artifacts/coverage/Trade-over-Aid-coverage.html"))
