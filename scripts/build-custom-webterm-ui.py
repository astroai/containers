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
        except Exception as e:
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
    </style>
    """

    # Define custom JS
    js_content = """
    <script>
    function copyCmd(cmd) {
      navigator.clipboard.writeText(cmd).then(() => {
        showToast('Copied \\"' + cmd + '\\" to clipboard! Paste it using Cmd+V or Ctrl+Shift+V.');
      }).catch(err => {
        console.error('Could not copy command: ', err);
      });
    }

    function showToast(message) {
      let container = document.getElementById('toast-container');
      if (!container) {
        container = document.createElement('div');
        container.id = 'toast-container';
        container.className = 'toast-container';
        document.body.appendChild(container);
      }
      const toast = document.createElement('div');
      toast.className = 'toast';
      toast.innerText = message;
      container.appendChild(toast);
      setTimeout(() => {
        toast.remove();
      }, 3000);
    }

    function toggleSidebar() {
      const sidebar = document.getElementById('sidebar');
      const toggleBtn = document.getElementById('toggle-sidebar-btn');
      if (sidebar.classList.contains('collapsed')) {
        sidebar.classList.remove('collapsed');
        toggleBtn.innerText = 'Collapse Sidebar';
      } else {
        sidebar.classList.add('collapsed');
        toggleBtn.innerText = 'Expand Sidebar';
      }
      // Trigger resize event so xterm.js fits correctly
      setTimeout(() => {
        window.dispatchEvent(new Event('resize'));
      }, 350);
    }

    function toggleFullscreen() {
      const sidebar = document.getElementById('sidebar');
      const toggleBtn = document.getElementById('toggle-sidebar-btn');
      sidebar.classList.add('collapsed');
      toggleBtn.innerText = 'Expand Sidebar';
      window.dispatchEvent(new Event('resize'));
      showToast('Sidebar collapsed for focus view.');
    }

    function copyTerminalText() {
      showToast('Select text in the terminal with mouse to copy automatically via tmux.');
    }

    function pasteTerminalText() {
      showToast('Press Cmd+V (Mac) or Ctrl+Shift+V (Linux/Windows) to paste.');
    }
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
            <button class="btn-action" onclick="copyTerminalText()">Copy Help</button>
            <button class="btn-action" onclick="pasteTerminalText()">Paste Help</button>
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
