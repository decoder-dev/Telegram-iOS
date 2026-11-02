"""Exercise the local DOM prototype in Chromium; never connects to Telegram."""

import json
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
URL = (ROOT / "prototype/index.html").as_uri()
OUTPUT = ROOT / "qa"


def run():
    results = []
    console_errors = []
    screenshots = OUTPUT / "screenshots"
    screenshots.mkdir(exist_ok=True)
    started = time.monotonic()

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page(viewport={"width": 1440, "height": 1100}, device_scale_factor=1)
        page.set_default_timeout(10000)
        page.on("pageerror", lambda error: console_errors.append(str(error)))

        def load(screen="02_chats", theme="light"):
            page.goto("about:blank")
            page.goto(f"{URL}#screen={screen}&theme={theme}")
            page.locator("#scene-title").wait_for()
            expected = "27_vault_locked" if screen == "12_vault" else screen
            assert f"screen={expected}" in page.url
            assert page.locator(f'.catalogue-link[data-go="{expected}"]').get_attribute("aria-current") == "page"

        def navigate(screen):
            page.locator(f'.catalogue-link[data-go="{screen}"]').click()

        def check(name, operation):
            try:
                operation()
                results.append({"name": name, "status": "PASS"})
            except Exception as error:
                results.append({"name": name, "status": "FAIL", "error": str(error)})
                page.screenshot(path=str(OUTPUT / "failure.png"))

        def send(text):
            page.get_by_role("textbox", name="Сообщение", exact=True).fill(text)
            page.get_by_role("button", name="Отправить сообщение", exact=True).click()

        def conversation():
            load("03_chat")
            send("Первое локальное сообщение")
            send("Второе локальное сообщение")
            assert page.locator("article.message").count() == 7
            navigate("24_settings")
            navigate("03_chat")
            assert page.locator("article.message").count() == 7
            assert page.get_by_text("Первое локальное сообщение", exact=True).count() == 1
            page.locator(".message .bubble").last.click()
            page.get_by_role("button", name="Изменить", exact=True).click()
            send("Исправленное сообщение")
            assert page.get_by_text("Второе локальное сообщение", exact=True).count() == 0
            assert page.get_by_text("Исправленное сообщение", exact=True).count() == 1
            page.locator(".message .bubble").first.click()
            page.get_by_role("button", name="Ответить", exact=True).click()
            send("Ответ с цитатой")
            assert page.locator(".quote").last.inner_text() == "Привет! Как насчёт встретиться вечером?"

        def injection():
            load("03_chat")
            payload = '<img src=x onerror="window.injected=true">'
            send(payload)
            assert page.locator(".message .bubble").last.inner_text() == payload
            assert page.locator(".message img").count() == 0
            assert page.evaluate("window.injected === undefined")

        def draft():
            load("03_chat")
            page.get_by_role("textbox", name="Сообщение", exact=True).fill("Неотправленный текст")
            page.locator("#dark").click()
            assert page.get_by_role("textbox", name="Сообщение", exact=True).input_value() == "Неотправленный текст"
            navigate("02_chats")
            navigate("03_chat")
            assert page.get_by_role("textbox", name="Сообщение", exact=True).input_value() == "Неотправленный текст"

        def settings():
            load("24_settings")
            toggle = page.get_by_role("switch", name="Звук в приложении")
            assert toggle.get_attribute("aria-checked") == "true"
            toggle.click()
            page.get_by_role("button", name="Оформление", exact=True).click()
            page.locator("#dark").click()
            page.locator("#back").click()
            assert page.get_by_role("switch", name="Звук в приложении").get_attribute("aria-checked") == "false"

        def search():
            load()
            field = page.get_by_role("searchbox", name="Поиск по чатам")
            field.fill("Анна")
            assert page.locator(".chat-row").count() == 1
            field.fill("НетТакогоКонтакта")
            assert page.locator(".chat-row").count() == 0
            assert page.get_by_text("Ничего не найдено.", exact=False).is_visible()

        def attachments():
            load("03_chat")
            page.get_by_role("button", name="Добавить вложение").click()
            assert page.get_by_role("dialog").is_visible()
            page.keyboard.press("Escape")
            assert not page.get_by_role("dialog").is_visible()
            page.get_by_role("button", name="Добавить вложение").click()
            page.get_by_role("button", name="Демонстрационное фото", exact=True).click()
            assert page.locator(".message .bubble").last.inner_text() == "[Фото · демонстрационный файл]"

        def reaction_delete():
            load("03_chat")
            page.locator(".message .bubble").last.click()
            page.get_by_role("button", name="Нравится", exact=True).click()
            assert page.locator(".reaction").count() == 1
            page.get_by_role("button", name="Убрать реакцию Нравится").click()
            assert page.locator(".reaction").count() == 0
            page.locator(".message .bubble").last.click()
            page.get_by_role("button", name="Удалить из демонстрации").click()
            page.get_by_role("button", name="Отмена", exact=True).click()
            assert page.locator("article.message").count() == 5
            page.locator(".message .bubble").last.click()
            page.get_by_role("button", name="Удалить из демонстрации").click()
            page.get_by_role("button", name="Удалить", exact=True).click()
            assert page.locator("article.message").count() == 4

        def vault():
            load("12_vault")
            assert "27_vault_locked" in page.url
            page.get_by_label("Демонстрационный код").fill("0000")
            page.get_by_role("button", name="Открыть демо").click()
            assert page.get_by_role("alert").inner_text() == "Неверный демонстрационный код"
            page.get_by_label("Демонстрационный код").fill("1234")
            page.get_by_role("button", name="Открыть демо").click()
            assert "12_vault" in page.url
            page.evaluate("Object.defineProperty(document, 'hidden', {value:true, configurable:true}); document.dispatchEvent(new Event('visibilitychange'))")
            assert "27_vault_locked" in page.url
            navigate("12_vault")
            assert "27_vault_locked" in page.url
            page.evaluate("Object.defineProperty(document, 'hidden', {value:false, configurable:true})")

        def reset():
            load("03_chat")
            send("Временное сообщение")
            page.locator("#reset").click()
            navigate("03_chat")
            assert page.locator("article.message").count() == 5

        def archive_selection():
            load()
            page.get_by_role("button", name="Изменить", exact=True).click()
            page.get_by_role("checkbox", name="Анна Смирнова, непрочитанных: 2").click()
            page.get_by_role("button", name="В архив · 1", exact=True).click()
            assert page.locator('.chat-row[data-peer="Анна Смирнова"]').count() == 0
            page.locator('.archive-row').click()
            assert page.locator('.chat-row[data-peer="Анна Смирнова"]').is_visible()
            assert page.locator('.chat-row').count() == 3

        def separate_chats():
            load('03_chat')
            page.get_by_role('textbox',name='Сообщение',exact=True).fill('Черновик для Анны')
            navigate('02_chats')
            page.locator('.chat-row[data-peer="Виктор Кузнецов"]').click()
            assert page.locator('.contact-button strong').inner_text() == 'Виктор Кузнецов'
            assert page.locator('article.message').count() == 0
            send('Сообщение Виктору')
            navigate('02_chats')
            page.locator('.chat-row[data-peer="Анна Смирнова"]').click()
            assert page.get_by_text('Сообщение Виктору', exact=True).count() == 0
            assert page.locator('article.message').count() == 5
            assert page.get_by_role('textbox',name='Сообщение',exact=True).input_value() == 'Черновик для Анны'

        check("send / history / edit / reply", conversation)
        check("message text cannot inject HTML", injection)
        check("draft survives theme and navigation", draft)
        check("settings switch survives theme and navigation", settings)
        check("chat search and empty results", search)
        check("attachment sheet Escape and demo send", attachments)
        check("reaction and confirmed deletion", reaction_delete)
        check("demo vault guards direct route and synthetic visibility event", vault)
        check("reset clears demonstration state", reset)
        check("select and archive chats in local state", archive_selection)
        check("private conversations keep separate messages", separate_chats)

        catalog = json.loads((ROOT / "reference/METADATA/screen_catalog.json").read_text())
        for theme in ["light", "dark"]:
            for scene in catalog:
                def route(scene_id=scene["id"], selected_theme=theme):
                    load(scene_id, selected_theme)
                    assert page.locator("#scene-title").inner_text()
                    image = page.locator(".reference-view img")
                    if image.count():
                        image.evaluate("image => image.decode()")
                        assert image.evaluate("image => image.naturalWidth === 1179 && image.naturalHeight === 2556")
                check(f"route and asset: {scene['id']} / {theme}", route)

        for screen in ["02_chats", "03_chat", "24_settings"]:
            for theme in ["light", "dark"]:
                for large in [False, True]:
                    def capture(screen_id=screen, selected_theme=theme, large_text=large):
                        load(screen_id, selected_theme)
                        page.locator("#large-text").set_checked(large_text)
                        assert page.locator(".device").evaluate("e => e.scrollWidth <= e.clientWidth")
                        page.locator(".device").screenshot(path=str(screenshots / f"{screen_id}-{selected_theme}-{'large' if large_text else 'normal'}.png"))
                    check(f"capture layout: {screen} / {theme} / large={large}", capture)

        def fallbacks():
            load('03_chat','dark')
            page.locator('#opaque').check()
            page.locator('#reduce-motion').check()
            assert page.locator('body').evaluate("e => getComputedStyle(e).getPropertyValue('--glass').trim() === getComputedStyle(e).getPropertyValue('--surface').trim()")
            page.locator('.device').screenshot(path=str(screenshots/'03_chat-dark-opaque-reduced-motion.png'))
        check('opaque and reduced motion controls', fallbacks)

        for width in [360, 390]:
            def narrow(viewport_width=width):
                page.set_viewport_size({"width":viewport_width, "height":1000})
                load("03_chat")
                assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
                assert page.locator("#message-input").bounding_box()["width"] > 100
            check(f"narrow viewport: {width}px", narrow)

        if console_errors:
            results.append({"name":"browser JavaScript errors", "status":"FAIL", "errors":console_errors})
        else:
            results.append({"name":"browser JavaScript errors", "status":"PASS"})
        report = dict(browser=browser.version, elapsed_seconds=round(time.monotonic()-started,2), results=results, native="NOT_RUN", visual_acceptance="PENDING", note="Route checks validate loading, not visual design or native behavior.")
        (OUTPUT / "prototype-tests.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n")
        browser.close()
    failed = [result for result in results if result["status"] == "FAIL"]
    print(json.dumps({"passed":len(results)-len(failed),"failed":failed},ensure_ascii=False))
    return bool(failed)


if __name__ == "__main__":
    raise SystemExit(run())
