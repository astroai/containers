#!/usr/bin/env python3
import sys
import re
import subprocess
import time
import urllib.request

def main():
    if len(sys.argv) < 2:
        print("Usage: build-custom-webterm-ui.py <output_html>")
        sys.exit(1)

    output_file = sys.argv[1]

    # Start ttyd in background to fetch default index.html
    port = "12345"
    print(f"Starting ttyd on port {port} to fetch default template...")
    p = subprocess.Popen(['ttyd', '-p', port, 'bash'])
    
    html = None
    success = False
    for i in range(20):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}") as response:
                html = response.read().decode('utf-8')
            success = True
            print("Successfully fetched ttyd template.")
            break
        except Exception:
            time.sleep(0.5)

    p.terminate()
    p.wait()

    if not success or not html:
        print("Error: Failed to fetch default template from ttyd")
        sys.exit(1)

    # Define custom CSS
    css_content = """
    <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap');

    :root {
      --bg-dark: #1e1e2e;
      --bg-sidebar: rgba(24, 24, 37, 0.75);
      --border-color: rgba(255, 255, 255, 0.08);
      --text-main: #cdd6f4;
      --text-muted: #a6adc8;
      --accent: #cba6f7;
      --accent-glow: rgba(203, 166, 247, 0.2);
      --btn-bg: rgba(255, 255, 255, 0.04);
      --btn-hover: rgba(255, 255, 255, 0.08);
      --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      --font-mono: 'JetBrains Mono', monospace;
    }

    body {
      margin: 0;
      padding: 0;
      background-color: var(--bg-dark) !important;
      color: var(--text-main);
      font-family: var(--font-sans);
      overflow: hidden;
    }

    .app-layout {
      display: flex;
      height: 100vh;
      width: 100vw;
      overflow: hidden;
      background: radial-gradient(circle at top right, rgba(203, 166, 247, 0.06), transparent 45%),
                  radial-gradient(circle at bottom left, rgba(137, 180, 250, 0.06), transparent 45%);
    }

    .sidebar {
      width: 280px;
      background-color: var(--bg-sidebar);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border-right: 1px solid var(--border-color);
      display: flex;
      flex-direction: column;
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      flex-shrink: 0;
      z-index: 10;
    }

    .sidebar.collapsed {
      width: 0;
      opacity: 0;
      pointer-events: none;
      border-right: none;
    }

    .sidebar-header {
      padding: 20px 24px;
      display: flex;
      align-items: center;
      gap: 12px;
      border-bottom: 1px solid var(--border-color);
    }

    .logo-dot {
      width: 10px;
      height: 10px;
      background-color: var(--accent);
      border-radius: 50%;
      box-shadow: 0 0 10px var(--accent);
    }

    .sidebar-header h1 {
      margin: 0;
      font-size: 15px;
      font-weight: 600;
      letter-spacing: -0.2px;
      background: linear-gradient(135deg, #cdd6f4, #cba6f7);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }

    .nav-section {
      padding: 16px 24px;
      border-bottom: 1px solid var(--border-color);
      display: flex;
      flex-direction: column;
      gap: 10px;
    }

    .nav-section h3 {
      margin: 0;
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 1px;
      color: var(--text-muted);
      font-weight: 700;
    }

    .nav-section ul {
      list-style: none;
      padding: 0;
      margin: 0;
      display: flex;
      flex-direction: column;
      gap: 6px;
    }

    .nav-section ul li a {
      display: block;
      padding: 8px 12px;
      border-radius: 6px;
      color: var(--text-main);
      text-decoration: none;
      font-size: 13px;
      font-weight: 500;
      background-color: var(--btn-bg);
      border: 1px solid transparent;
      transition: all 0.2s ease;
    }

    .nav-section ul li a:hover {
      background-color: var(--btn-hover);
      border-color: var(--border-color);
      transform: translateX(3px);
      color: #fff;
    }

    .command-buttons {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 6px;
    }

    .btn-cmd {
      padding: 6px 10px;
      border-radius: 6px;
      background-color: var(--btn-bg);
      border: 1px solid var(--border-color);
      color: var(--text-main);
      font-family: var(--font-mono);
      font-size: 11px;
      cursor: pointer;
      text-align: left;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      transition: all 0.2s ease;
    }

    .btn-cmd:hover {
      background-color: var(--btn-hover);
      border-color: var(--accent);
      box-shadow: 0 0 8px var(--accent-glow);
      color: #fff;
    }

    .cheatsheet-grid {
      display: flex;
      flex-direction: column;
      gap: 6px;
      max-height: 160px;
      overflow-y: auto;
      padding-right: 4px;
    }

    .cheatsheet-grid::-webkit-scrollbar {
      width: 4px;
    }

    .cheatsheet-grid::-webkit-scrollbar-thumb {
      background-color: var(--border-color);
      border-radius: 2px;
    }

    .cheat-item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 12px;
      padding: 2px 0;
    }

    .cheat-item span:last-child {
      color: var(--text-muted);
    }

    .key {
      font-family: var(--font-mono);
      background-color: var(--btn-bg);
      border: 1px solid var(--border-color);
      padding: 1px 5px;
      border-radius: 4px;
      font-size: 10px;
      color: var(--accent);
    }

    .sidebar-footer {
      margin-top: auto;
      padding: 16px 24px;
      border-top: 1px solid var(--border-color);
    }

    .btn-toggle {
      width: 100%;
      padding: 8px;
      border-radius: 6px;
      background-color: var(--btn-bg);
      border: 1px solid var(--border-color);
      color: var(--text-muted);
      font-size: 12px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s ease;
    }

    .btn-toggle:hover {
      background-color: var(--btn-hover);
      color: #fff;
    }

    .main-content {
      flex-grow: 1;
      display: flex;
      flex-direction: column;
      height: 100vh;
      overflow: hidden;
    }

    .top-bar {
      height: 56px;
      padding: 0 24px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      border-bottom: 1px solid var(--border-color);
      background-color: rgba(30, 30, 46, 0.4);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
    }

    .session-info {
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .status-badge {
      font-size: 11px;
      font-weight: 600;
      padding: 3px 8px;
      border-radius: 20px;
      background-color: rgba(166, 227, 161, 0.1);
      color: #a6e3a1;
      border: 1px solid rgba(166, 227, 161, 0.2);
    }

    #session-display {
      font-size: 13px;
      font-weight: 500;
      color: var(--text-muted);
    }

    .top-actions {
      display: flex;
      gap: 8px;
    }

    .btn-action {
      padding: 6px 12px;
      border-radius: 6px;
      background-color: var(--btn-bg);
      border: 1px solid var(--border-color);
      color: var(--text-main);
      font-size: 12px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s ease;
    }

    .btn-action:hover {
      background-color: var(--btn-hover);
      border-color: var(--accent);
      color: #fff;
    }

    #terminal-container-wrapper {
      flex-grow: 1;
      position: relative;
      padding: 12px;
      background-color: rgba(24, 24, 37, 0.2);
      overflow: hidden;
    }

    #terminal-container {
      width: 100% !important;
      height: 100% !important;
      border-radius: 6px;
      overflow: hidden;
      border: 1px solid var(--border-color);
    }

    /* Notification toast styling */
    .toast-container {
      position: fixed;
      bottom: 24px;
      right: 24px;
      display: flex;
      flex-direction: column;
      gap: 8px;
      z-index: 1000;
    }

    .toast {
      padding: 12px 20px;
      border-radius: 8px;
      background-color: #313244;
      border: 1px solid var(--accent);
      color: #fff;
      font-size: 13px;
      font-weight: 500;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
      animation: slideIn 0.3s cubic-bezier(0.4, 0, 0.2, 1), fadeOut 0.3s 2.7s forwards;
    }

    @keyframes slideIn {
      from { transform: translateY(20px); opacity: 0; }
      to { transform: translateY(0); opacity: 1; }
    }

    @keyframes fadeOut {
      from { opacity: 1; }
      to { opacity: 0; }
    }

    .astroai-ctx {
      position: fixed;
      z-index: 2000;
      min-width: 180px;
      padding: 6px;
      border-radius: 8px;
      background: #313244;
      border: 1px solid rgba(255, 255, 255, 0.12);
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
      display: flex;
      flex-direction: column;
      gap: 2px;
    }

    .astroai-ctx button {
      appearance: none;
      border: 0;
      background: transparent;
      color: #cdd6f4;
      text-align: left;
      padding: 8px 10px;
      border-radius: 6px;
      font: 500 12px/1.2 Inter, sans-serif;
      cursor: pointer;
    }

    .astroai-ctx button:hover {
      background: rgba(203, 166, 247, 0.15);
      color: #fff;
    }
    </style>
    """

    # Define custom JS
    # ttyd 1.7.7 has no ClipboardAddon; inject OSC 52 + paste/copy UX via window.term.
    js_content = r"""
    <script>
    (function () {
      var lastOscCopy = '';
      var ctxMenu = null;

      function isMac() {
        return /Mac|iPhone|iPad|iPod/.test(navigator.platform || '') ||
          /Mac/.test(navigator.userAgent || '');
      }

      function showToast(message) {
        var container = document.getElementById('toast-container');
        if (!container) {
          container = document.createElement('div');
          container.id = 'toast-container';
          container.className = 'toast-container';
          document.body.appendChild(container);
        }
        var toast = document.createElement('div');
        toast.className = 'toast';
        toast.innerText = message;
        container.appendChild(toast);
        setTimeout(function () { toast.remove(); }, 2800);
      }

      function writeClipboardText(text) {
        if (!text) return Promise.reject(new Error('empty'));
        lastOscCopy = text;
        if (navigator.clipboard && navigator.clipboard.writeText) {
          return navigator.clipboard.writeText(text).catch(function () {
            return execCommandCopy(text);
          });
        }
        return execCommandCopy(text);
      }

      function execCommandCopy(text) {
        return new Promise(function (resolve, reject) {
          var ta = document.createElement('textarea');
          ta.value = text;
          ta.setAttribute('readonly', '');
          ta.style.position = 'fixed';
          ta.style.left = '-9999px';
          document.body.appendChild(ta);
          ta.select();
          ta.setSelectionRange(0, text.length);
          try {
            if (document.execCommand('copy')) resolve();
            else reject(new Error('execCommand copy failed'));
          } catch (e) {
            reject(e);
          } finally {
            ta.remove();
          }
        });
      }

      function decodeOsc52Payload(data) {
        var semi = data.indexOf(';');
        if (semi < 0) return null;
        var b64 = data.substring(semi + 1);
        if (!b64 || b64.charAt(0) === '?') return null;
        try {
          var bin = atob(b64);
          var bytes = new Uint8Array(bin.length);
          for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
          return new TextDecoder().decode(bytes);
        } catch (e) {
          return null;
        }
      }

      function installOsc52Handler(term) {
        if (!term || !term.parser || typeof term.parser.registerOscHandler !== 'function') return false;
        if (term.__astroaiOsc52) return true;
        term.parser.registerOscHandler(52, function (data) {
          var text = decodeOsc52Payload(data);
          if (text == null) return false;
          writeClipboardText(text).then(function () {
            showToast('Copied (' + text.length + ' chars)');
          }).catch(function () {});
          return true;
        });
        term.__astroaiOsc52 = true;
        return true;
      }

      function installSelectionAutoCopy(term) {
        if (!term || typeof term.onSelectionChange !== 'function') return;
        if (term.__astroaiSelCopy) return;
        term.__astroaiSelCopy = true;
        term.onSelectionChange(function () {
          var sel = term.getSelection ? term.getSelection() : '';
          if (!sel) return;
          writeClipboardText(sel).catch(function () {});
        });
      }

      function pasteIntoTerminal(text) {
        if (!text) return false;
        var term = window.term;
        if (term && typeof term.paste === 'function') {
          term.paste(text);
          return true;
        }
        if (term && typeof term.input === 'function') {
          term.input('\x1b[200~' + text + '\x1b[201~');
          return true;
        }
        return false;
      }

      function getTermSelection() {
        var term = window.term;
        return (term && term.getSelection) ? (term.getSelection() || '') : '';
      }

      function copySelection() {
        var sel = getTermSelection() || lastOscCopy;
        if (!sel) {
          showToast('No selection — drag to select (or Toggle mouse, then drag).');
          return;
        }
        writeClipboardText(sel).then(function () {
          showToast('Copied (' + sel.length + ' chars)');
        }).catch(function () {
          showToast('Clipboard write failed (permission?).');
        });
      }

      function pasteFromClipboard() {
        function failHint() {
          showToast(isMac()
            ? 'Use Cmd+V to paste (clipboard permission blocked).'
            : 'Use Ctrl+Shift+V to paste (clipboard permission blocked).');
        }
        if (!navigator.clipboard || !navigator.clipboard.readText) {
          failHint();
          return;
        }
        navigator.clipboard.readText().then(function (text) {
          if (!text) {
            showToast('Clipboard is empty.');
            return;
          }
          if (pasteIntoTerminal(text)) showToast('Pasted (' + text.length + ' chars)');
          else failHint();
        }).catch(failHint);
      }

      function sendTmuxKeys(keys) {
        var term = window.term;
        if (!term || typeof term.input !== 'function') {
          showToast('Terminal not ready.');
          return false;
        }
        term.input(keys);
        return true;
      }

      function toggleTmuxMouse() {
        if (sendTmuxKeys('\x02m')) {
          showToast('Toggled tmux mouse (status line shows on/off).');
        }
      }

      function hideCtxMenu() {
        if (ctxMenu) {
          ctxMenu.remove();
          ctxMenu = null;
        }
      }

      function showCtxMenu(x, y) {
        hideCtxMenu();
        ctxMenu = document.createElement('div');
        ctxMenu.className = 'astroai-ctx';
        ctxMenu.style.left = x + 'px';
        ctxMenu.style.top = y + 'px';
        [
          { label: 'Copy', fn: copySelection },
          { label: 'Paste', fn: pasteFromClipboard },
          { label: 'Toggle tmux mouse', fn: toggleTmuxMouse }
        ].forEach(function (item) {
          var b = document.createElement('button');
          b.type = 'button';
          b.textContent = item.label;
          b.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            hideCtxMenu();
            item.fn();
          });
          ctxMenu.appendChild(b);
        });
        document.body.appendChild(ctxMenu);
      }

      function copyCmd(cmd) {
        writeClipboardText(cmd).then(function () {
          showToast('Copied "' + cmd + '" — Paste or ' + (isMac() ? 'Cmd+V' : 'Ctrl+Shift+V'));
        }).catch(function () {
          showToast('Clipboard write failed (permission?).');
        });
      }

      function toggleSidebar() {
        var sidebar = document.getElementById('sidebar');
        var toggleBtn = document.getElementById('toggle-sidebar-btn');
        if (sidebar.classList.contains('collapsed')) {
          sidebar.classList.remove('collapsed');
          toggleBtn.innerText = 'Collapse Sidebar';
        } else {
          sidebar.classList.add('collapsed');
          toggleBtn.innerText = 'Expand Sidebar';
        }
        setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 350);
      }

      function toggleFullscreen() {
        var sidebar = document.getElementById('sidebar');
        var toggleBtn = document.getElementById('toggle-sidebar-btn');
        sidebar.classList.add('collapsed');
        toggleBtn.innerText = 'Expand Sidebar';
        window.dispatchEvent(new Event('resize'));
        showToast('Sidebar collapsed for focus view.');
      }

      function onKeydown(e) {
        var key = (e.key || '').toLowerCase();
        var sel = getTermSelection();
        // Mac: Cmd+C copies selection. Linux: Ctrl+Shift+C only — never steal Ctrl+C (SIGINT).
        var wantCopy = isMac()
          ? (e.metaKey && key === 'c' && !e.shiftKey)
          : (e.ctrlKey && e.shiftKey && key === 'c');
        if (wantCopy && sel) {
          e.preventDefault();
          writeClipboardText(sel).then(function () {
            showToast('Copied (' + sel.length + ' chars)');
          }).catch(function () {});
        }
      }

      function onContextMenu(e) {
        var wrap = document.getElementById('terminal-container-wrapper');
        if (!wrap || !wrap.contains(e.target)) return;
        e.preventDefault();
        showCtxMenu(e.clientX, e.clientY);
      }

      function waitForTermAndInstallClipboard() {
        var tries = 0;
        var timer = setInterval(function () {
          tries += 1;
          if (window.term) {
            installOsc52Handler(window.term);
            installSelectionAutoCopy(window.term);
            if (window.term.__astroaiOsc52) {
              clearInterval(timer);
              return;
            }
          }
          if (tries > 80) clearInterval(timer);
        }, 250);
      }

      window.copyCmd = copyCmd;
      window.showToast = showToast;
      window.toggleSidebar = toggleSidebar;
      window.toggleFullscreen = toggleFullscreen;
      window.copySelection = copySelection;
      window.pasteFromClipboard = pasteFromClipboard;
      window.toggleTmuxMouse = toggleTmuxMouse;

      document.addEventListener('keydown', onKeydown, true);
      document.addEventListener('click', hideCtxMenu);
      document.addEventListener('contextmenu', onContextMenu);
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', waitForTermAndInstallClipboard);
      } else {
        waitForTermAndInstallClipboard();
      }
    })();
    </script>
    """

    # Define wrapper markup
    wrapper_html = """
    <div class="app-layout">
      <aside class="sidebar" id="sidebar">
        <div class="sidebar-header">
          <div class="logo-dot"></div>
          <h1>AstroAI Webterm</h1>
        </div>
        
        <nav class="nav-section">
          <h3>Quick Launch</h3>
          <ul>
            <li><a href="/session/notebook/" target="_blank">Jupyter Notebook</a></li>
            <li><a href="/session/vscode/" target="_blank">VS Code</a></li>
            <li><a href="/session/marimo/" target="_blank">Marimo Editor</a></li>
            <li><a href="/session/ray/" target="_blank">Ray Manager</a></li>
          </ul>
        </nav>

        <div class="nav-section">
          <h3>Quick Copy Commands</h3>
          <div class="command-buttons">
            <button class="btn-cmd" onclick="copyCmd('git status')">git status</button>
            <button class="btn-cmd" onclick="copyCmd('nvidia-smi')">nvidia-smi</button>
            <button class="btn-cmd" onclick="copyCmd('htop')">htop</button>
            <button class="btn-cmd" onclick="copyCmd('df -h')">df -h</button>
            <button class="btn-cmd" onclick="copyCmd('/opt/astroai/bin/canfar-verify.sh')">verify env</button>
            <button class="btn-cmd" onclick="copyCmd('tmux attach')">attach tmux</button>
          </div>
        </div>

        <div class="nav-section">
          <h3>Tmux Cheatsheet</h3>
          <div class="cheatsheet-grid">
            <div class="cheat-item"><span class="key">Ctrl+b c</span><span>New Window</span></div>
            <div class="cheat-item"><span class="key">Ctrl+b ,</span><span>Rename Window</span></div>
            <div class="cheat-item"><span class="key">Ctrl+b n/p</span><span>Next/Prev Window</span></div>
            <div class="cheat-item"><span class="key">Ctrl+b %</span><span>Split Vertically</span></div>
            <div class="cheat-item"><span class="key">Ctrl+b &quot;</span><span>Split Horizontally</span></div>
            <div class="cheat-item"><span class="key">Ctrl+b o</span><span>Switch Pane</span></div>
            <div class="cheat-item"><span class="key">Ctrl+b z</span><span>Toggle Zoom</span></div>
            <div class="cheat-item"><span class="key">Ctrl+b [</span><span>Copy Mode</span></div>
            <div class="cheat-item"><span class="key">v / y</span><span>Select / Yank</span></div>
            <div class="cheat-item"><span class="key">Ctrl+b m</span><span>Toggle mouse</span></div>
          </div>
        </div>

        <div class="nav-section">
          <h3>Files</h3>
          <div class="command-buttons">
            <button class="btn-cmd" onclick="copyCmd('peek README.md')">peek README.md</button>
            <button class="btn-cmd" onclick="copyCmd('peek -h')">peek -h</button>
          </div>
        </div>

        <div class="sidebar-footer">
          <button class="btn-toggle" id="toggle-sidebar-btn" onclick="toggleSidebar()">Collapse Sidebar</button>
        </div>
      </aside>

      <main class="main-content">
        <header class="top-bar">
          <div class="session-info">
            <span class="status-badge">Session Connected</span>
            <span id="session-display">AstroAI Web Terminal</span>
          </div>
          <div class="top-actions">
            <button class="btn-action" onclick="copySelection()">Copy</button>
            <button class="btn-action" onclick="pasteFromClipboard()">Paste</button>
            <button class="btn-action" onclick="toggleTmuxMouse()">Toggle mouse</button>
            <button class="btn-action" onclick="toggleFullscreen()">Fullscreen</button>
          </div>
        </header>
        <div id="terminal-container-wrapper">
          <div id="terminal-container"></div>
        </div>
      </main>
    </div>
    """

    # 1. Inject CSS before </head>
    if '</head>' in html:
        html = html.replace('</head>', css_content + '\n</head>')
    else:
        print("Warning: </head> not found, appending CSS to body")
        html += css_content

    # 2. Inject Wrapper Markup replacing <div id="terminal-container"></div>
    # Support multiple formats of terminal-container div
    regex_term = re.compile(r'<div\s+id=["\']terminal-container["\']\s*>\s*</div>')
    if regex_term.search(html):
        html = regex_term.sub(wrapper_html, html)
    else:
        # Fallback to standard replace
        if '<div id="terminal-container"></div>' in html:
            html = html.replace('<div id="terminal-container"></div>', wrapper_html)
        else:
            print("Warning: terminal-container div not found, inserting wrapper body")
            # If not found, try to replace <body> contents or add at top of body
            if '<body>' in html:
                html = html.replace('<body>', '<body>\n' + wrapper_html)

    # 3. Inject JS before </body>
    if '</body>' in html:
        html = html.replace('</body>', js_content + '\n</body>')
    else:
        html += js_content

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(html)

    print(f"Successfully wrote custom webterm UI to {output_file}")

if __name__ == "__main__":
    main()
