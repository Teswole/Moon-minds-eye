# 2026-11-14 4:35 PM CST — opens https://moon-minds-eye.onrender.com like an iPhone and reports what the weather card shows
import asyncio, base64, io
from playwright.async_api import async_playwright
from PIL import Image

URL = "https://moon-minds-eye.onrender.com/"


def small_b64(png_bytes, width=360):
    im = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    im.thumbnail((width, 2000))
    out = io.BytesIO()
    im.save(out, "JPEG", quality=70)
    return base64.b64encode(out.getvalue()).decode()


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        ctx = await b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2,
                                  geolocation={"latitude": 30.2, "longitude": -92.0}, permissions=["geolocation"],
                                  user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1")
        pg = await ctx.new_page()
        logs = []
        pg.on("console", lambda m: logs.append(f"console {m.type}: {m.text}") if m.type in ("error", "warning") else None)
        pg.on("pageerror", lambda e: logs.append(f"pageerror: {e}"))
        pg.on("requestfailed", lambda r: logs.append(f"failed: {r.url[:120]} {r.failure}"))
        pg.on("response", lambda r: logs.append(f"http {r.status}: {r.url[:120]}") if r.status >= 400 else None)
        await pg.goto(URL, wait_until="networkidle")
        await pg.wait_for_timeout(9000)
        await pg.evaluate("document.querySelector('.tabbar').style.display='none'")
        card = await pg.query_selector("#wxCard")
        await card.scroll_into_view_if_needed()
        await pg.wait_for_timeout(2500)
        info = await pg.evaluate("""() => ({score: document.getElementById('wxScore').textContent,
            label: document.getElementById('wxLabel').textContent, frame: document.getElementById('wxFrame').textContent,
            mapMsg: (document.querySelector('#wxMap .wxMsg')||{}).textContent || '', leaflet: !!window.L,
            tiles: document.querySelectorAll('#wxMap img.leaflet-tile').length,
            tilesLoaded: [...document.querySelectorAll('#wxMap img.leaflet-tile')].filter(i => i.complete && i.naturalWidth > 0).length,
            version: document.documentElement.outerHTML.slice(0, 80)})""")
        print("INFO radar view:", info)
        print("B64 radar", small_b64(await card.screenshot()))
        await pg.click("#wxCloudBtn")
        await pg.wait_for_timeout(6000)
        info = await pg.evaluate("""() => ({frame: document.getElementById('wxFrame').textContent,
            tiles: document.querySelectorAll('#wxMap img.leaflet-tile').length,
            tilesLoaded: [...document.querySelectorAll('#wxMap img.leaflet-tile')].filter(i => i.complete && i.naturalWidth > 0).length})""")
        print("INFO clouds view:", info)
        print("B64 clouds", small_b64(await card.screenshot()))
        for line in logs[:40]:
            print("LOG", line)
        await b.close()

asyncio.run(main())
