"""Exercise the standalone country atlas in Chromium. Requires Python Playwright."""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
import sys
from threading import Thread
from playwright.sync_api import sync_playwright, expect


def run(path):
    html = path.read_bytes()

    class PageHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/atlas.html":
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)

        def log_message(self, *args):
            pass

    with ThreadingHTTPServer(("127.0.0.1", 0), PageHandler) as server, sync_playwright() as pw:
        Thread(target=server.serve_forever, daemon=True).start()
        browser = pw.chromium.launch(executable_path=os.getenv("CHROMIUM_PATH") or shutil.which("chromium"))
        context = browser.new_context(viewport={"width": 1440, "height": 1030}, accept_downloads=True)
        page = context.new_page()
        page.set_default_timeout(6000)
        errors, requests = [], []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("request", lambda r: requests.append(r.url))
        url = f"http://127.0.0.1:{server.server_port}/atlas.html"
        assert page.goto(url).ok
        context.set_offline(True)
        node = page.locator

        def pick(term):
            node("#search").fill(term)
            node("#search").press("ArrowDown")
            node("#search").press("Enter")

        def tab(name):
            node(f'[data-tab="{name}"]').click()

        def contains(selector, text):
            expect(node(selector)).to_contain_text(text)

        contains("#countryName", "Honduras")
        assert node('#map [data-code]').evaluate_all("(nodes) => new Set(nodes.map(n => n.dataset.code)).size") == 250
        assert node("#map circle[data-code=GIB]").count() == 1
        assert page.evaluate("document.fonts.check('16px \"DM Sans\"') && document.fonts.check('16px \"Instrument Serif\"')")
        contains("#profileStats", "FY 2024")
        contains("#profileStats", "CY 2023")
        node('[data-history="fa"]').click()
        contains("#drawerBody", "$40,002,719.00")
        node("#closeDrawer").click()
        node('[data-record-id="hnd-cost"]').click()
        contains("#drawerBody", "> $15M / year")
        contains("#drawerBody", "Printed p. 20, Puerto Cortés")
        assert node('#drawerBody a[href^="https://"]').count() >= 1
        node("#drawerBody [data-program]").click()
        contains("#drawerTitle", "Program record")
        node("#closeDrawer").click()

        node("[data-jump=Funding]").click()
        expect(node("#sourceFilter")).to_have_value("ppi")
        contains(".pager", "1–6 of 6")
        assert set(node(".sourceLine").all_text_contents()) == {"World Bank PPI"}
        node("button.rowlink").first.click()
        contains("#drawerBody", "Instrument")
        contains("#drawerBody", "Record locator")
        node("#closeDrawer").click()
        tab("Programs")
        contains(".pager", "1–12 of 755")
        node('[data-page="1"]').click()
        contains(".pager", "13–24 of 755")
        node("#donor").select_option("CHN")
        contains(".pager", "1–7 of 7")
        node("#rowQuery").fill("missing-source-xy123")
        contains("#records", "No records match")
        tab("Trade context")
        contains("#evidence", "2007")
        contains("#evidence", "2.4 days")

        node("#mapMode").select_option("equity")
        contains("#legend", "No paired amounts")
        assert node("path[data-code=BRA]").first.get_attribute("fill") == "#c18462"
        assert node("path[data-code=HND]").first.get_attribute("fill") == "#566f71"
        node("path[data-code=BRA]").first.click()
        contains("#countryName", "Brazil")
        tab("Overview")
        contains(".overviewGrid", "$417.63M")
        contains(".overviewGrid", "$1.59B")
        contains(".overviewGrid", "9 of 31 sponsor records")
        node("#zoomIn").click()
        assert "scale(1.7)" in node("#map > g").get_attribute("transform")
        node("#resetMap").click()
        assert "scale(1)" in node("#map > g").get_attribute("transform")
        node("#mapMode").select_option("coverage")

        page.keyboard.press("/")
        expect(node("#search")).to_be_focused()
        node("#search").fill("xyzzy-no-country")
        contains("#matches", "No matching country")
        pick("GIB")
        contains("#countryName", "Gibraltar")
        pick("Kosovo")
        contains("#location", "XKX")
        pick("ATA")
        assert node(".profileStat .metric").all_text_contents() == ["No observation"] * 2
        tab("Programs")
        contains("#records", "No program records")
        pick("Ethiopia")
        tab("Results")
        node("#donor").select_option("CHN")
        contains("#records", "Dire Dawa")
        node("button.rowlink").first.click()
        contains("#drawerBody", "4 hours")
        contains("#drawerBody", "Baseline")
        page.keyboard.press("Escape")
        expect(node("#drawer")).not_to_be_visible()
        with page.expect_download() as download:
            node("#download").click()
        exported = json.loads(download.value.path().read_text())
        assert download.value.suggested_filename == "ETH-country-evidence.json"
        assert exported["iso3"] == "ETH" and exported["code_system"] == "ISO 3166-1"
        assert all(r["iso3"] == "ETH" for k in ["program", "result", "finance", "context"] for r in exported[k])
        used = {r["source_id"] for table in ("program", "context") for r in exported[table]}
        assert used | {"iso"} == {s["source_id"] for s in exported["sources"]}
        assert any(r["unit"] == "hours" and r["actual"] == 4 and r["provider"] == "CHN" for r in exported["result"])
        node("#sourcesBtn").click()
        contains("#drawerBody", "political influence")
        node("summary", has_text="Country matching exclusions").click()
        assert node("#drawerBody tbody tr").count() == 265
        assert requests == [url], requests

        # Start a second reader fully offline, including first paint and font loading.
        mobile = browser.new_context(viewport={"width": 390, "height": 844}, offline=True)
        phone = mobile.new_page()
        phone.on("pageerror", lambda e: errors.append(str(e)))
        network = []
        phone.on("request", lambda r: network.append(r.url))
        phone.set_content(html.decode("utf-8"), wait_until="load", timeout=45000)
        expect(phone.locator("#countryName")).to_have_text("Honduras")
        phone.locator('[data-tab="Funding"]').click()
        phone.locator("#sourceFilter").select_option("ppi")
        phone.locator("button.rowlink").first.click()
        expect(phone.locator("#drawerTitle")).to_have_text("Funding record")
        phone.locator("#closeDrawer").click()
        assert phone.evaluate("document.documentElement.scrollWidth <= innerWidth")
        assert not [url for url in network if not url.startswith("data:")], network
        assert not errors, errors
        mobile.close()
        context.close()
        browser.close()
        server.shutdown()
    print("Chromium desktop and offline mobile checks passed, including map layers, all 250 selectors, "
          "financial totals, results, citations, filtering, pagination, country export and missing data.")


if __name__ == "__main__":
    run(Path(sys.argv[1] if len(sys.argv) > 1 else "artifacts/Trade-over-Aid-Atlas.html"))
