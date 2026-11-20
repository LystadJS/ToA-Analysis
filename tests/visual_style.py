"""Shared typography assertions for the two self-contained browser builds."""
def assert_typography(page, numeric_selector):
    for selector, family in [("h1", "EB Garamond"), ("body", "Atkinson Hyperlegible Next"),
                             (numeric_selector, "JetBrains Mono")]:
        face = page.locator(selector).first.evaluate("""async (node) => {
            const family = getComputedStyle(node).fontFamily.split(',')[0].replace(/["']/g, '').trim();
            const faces = await document.fonts.load('16px "' + family + '"', node.textContent || '0123');
            return [family, faces.length > 0 && faces.every(face => face.status === 'loaded')];
        }""")
        assert face == [family, True], (selector, face)
