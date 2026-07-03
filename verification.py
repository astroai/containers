from playwright.sync_api import sync_playwright

def run_cuj(page):
    page.goto("http://127.0.0.1:8000")
    page.wait_for_timeout(500)

    # Trigger 'Stop cluster' and accept the confirmation dialog
    page.once("dialog", lambda dialog: dialog.accept())
    page.locator('form[action="/actions/stop-cluster"] button[type="submit"]').click()
    page.wait_for_timeout(1000)

    # Trigger 'Clean orphaned workers' and accept the confirmation dialog
    page.once("dialog", lambda dialog: dialog.accept())
    #page.locator('form[action="/actions/clean-orphans"] button[type="submit"]').click()
    page.wait_for_timeout(1000)

    page.screenshot(path="/home/jules/verification/screenshots/verification.png")
    page.wait_for_timeout(1000)

if __name__ == "__main__":
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            record_video_dir="/home/jules/verification/videos"
        )
        page = context.new_page()
        try:
            run_cuj(page)
        finally:
            context.close()
            browser.close()
