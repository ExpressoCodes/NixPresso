# NixStore — "Updates" tab patch

Adds a third tab to the NixStore TUI that shows dotfiles git status and lets
you apply upstream updates without leaving NixStore. Apply these changes to
the `nixstore` repo (`nixstore/core.py` and `nixstore/tui.py`).

---

## nixstore/core.py — add after the `notify()` function

```python
# ── dotfiles update helpers ────────────────────────────────────────────────

import shutil

VARS_FILE = Path("/etc/nixos/.dotfiles-vars")


def read_dotfiles_vars() -> dict[str, str]:
    """Parse /etc/nixos/.dotfiles-vars written by install.sh."""
    if not VARS_FILE.exists():
        return {}
    result = {}
    for line in VARS_FILE.read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            result[k.strip()] = v.strip()
    return result


@dataclass
class DotfilesStatus:
    repo: Path
    local_rev: str
    remote_rev: str
    count: int
    commits: list[str]   # one-line summaries, newest first

    @property
    def up_to_date(self) -> bool:
        return self.local_rev == self.remote_rev


def check_dotfiles_updates() -> DotfilesStatus | None:
    """Fetch origin and return status, or None if repo/network unavailable."""
    vars_ = read_dotfiles_vars()
    repo_str = vars_.get("DOTFILES_REPO")
    if not repo_str:
        return None
    repo = Path(repo_str)
    if not (repo / ".git").exists():
        return None
    git = shutil.which("git") or "git"

    def run(*args: str) -> str:
        r = subprocess.run([git, "-C", str(repo), *args],
                           capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else ""

    run("fetch", "--quiet", "origin")
    local = run("rev-parse", "HEAD")
    remote = (run("rev-parse", "origin/HEAD")
              or run("rev-parse", "origin/main")
              or run("rev-parse", "origin/master"))
    if not local or not remote:
        return None
    count = int(run("rev-list", "--count", f"HEAD..{remote}") or "0")
    commits = [l for l in run("log", "--oneline", f"HEAD..{remote}").splitlines() if l]
    return DotfilesStatus(repo=repo, local_rev=local, remote_rev=remote,
                          count=count, commits=commits)


async def run_dotfiles_update(repo: Path, password: str,
                              log_cb) -> bool:
    """Run update.sh with sudo, streaming output to log_cb(line)."""
    script = repo / "update.sh"
    if not script.exists():
        await log_cb(f"update.sh not found in {repo}")
        return False
    proc = await asyncio.create_subprocess_exec(
        "sudo", "-S", "-k", "-p", "", str(script),
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    proc.stdin.write((password + "\n").encode())
    await proc.stdin.drain()
    proc.stdin.close()
    del password
    async for raw in proc.stdout:
        await log_cb(raw.decode(errors="replace").rstrip("\n"))
    await proc.wait()
    return proc.returncode == 0
```

---

## nixstore/tui.py — additions

### 1. Add `UpdateScreen` class (after `ApplyScreen`, before `NixStore`)

```python
class UpdateScreen(ModalScreen[bool]):
    """Check for and apply dotfiles upstream updates."""

    BINDINGS = [Binding("escape", "close", "Close")]

    def __init__(self) -> None:
        super().__init__()
        self.running = False
        self.succeeded = False

    def compose(self) -> ComposeResult:
        with Vertical(id="dialog"):
            yield Label("Dotfiles updates", id="dialog-title")
            yield Static(id="update-status")
            yield Input(password=True, placeholder="sudo password (needed for nixos-rebuild)", id="update-password")
            yield RichLog(id="update-log", wrap=True, markup=False)
            yield Label("Checking…", id="update-footer")

    def on_mount(self) -> None:
        self.query_one("#update-log").display = False
        self.query_one("#update-password").display = False
        self.check_updates()

    def set_footer(self, text: str, style: str = "") -> None:
        self.query_one("#update-footer", Label).update(Text(text, style=style))

    def action_close(self) -> None:
        if not self.running:
            self.dismiss(self.succeeded)

    @work(exclusive=True)
    async def check_updates(self) -> None:
        self.running = True
        try:
            status = await asyncio.to_thread(core.check_dotfiles_updates)
            if status is None:
                self.query_one("#update-status", Static).update(
                    Text("Dotfiles repo not found.\nRun install.sh first.", "dim"))
                self.set_footer("Esc: close")
                return
            if status.up_to_date:
                self.query_one("#update-status", Static).update(
                    Text("✓ Already up to date.", "bold green"))
                self.set_footer("Esc: close")
                return
            summary = Text()
            summary.append(f"{status.count} update(s) available:\n\n", "bold")
            for c in status.commits[:8]:
                summary.append(f"  {c}\n", "dim")
            self.query_one("#update-status", Static).update(summary)
            self.query_one("#update-password").display = True
            self.query_one("#update-password").focus()
            self.set_footer("Enter sudo password to apply · Esc: cancel")
            self._repo = status.repo
        finally:
            self.running = False

    @on(Input.Submitted, "#update-password")
    def password_submitted(self, event: Input.Submitted) -> None:
        if not self.running and not self.succeeded:
            password = event.value
            event.input.value = ""
            self.apply_updates(password)

    @work(exclusive=True)
    async def apply_updates(self, password: str) -> None:
        self.running = True
        log = self.query_one("#update-log", RichLog)
        self.query_one("#update-password").display = False
        log.display = True
        self.set_footer("Updating… (this can take a while)", "bold yellow")
        try:
            async def write_log(line: str) -> None:
                log.write(Text.from_ansi(line))
            ok = await core.run_dotfiles_update(self._repo, password, write_log)
            if ok:
                self.succeeded = True
                self.set_footer("✓ Done — Esc: back · Ctrl+Q: quit", "bold green")
                core.notify("Dotfiles updated", "System config is up to date")
            else:
                self.set_footer("✗ Update failed — see log above · Esc: back", "bold red")
                core.notify("Dotfiles update failed", "", "critical")
        finally:
            self.running = False
```

### 2. Add binding to `NixStore.BINDINGS`

```python
BINDINGS = [
    Binding("tab", "next_tab", "Switch tab", priority=True),
    Binding("ctrl+s", "apply", "Apply changes"),
    Binding("ctrl+u", "updates", "Check updates"),   # ← add this
    Binding("escape", "back", "Clear / quit"),
]
```

### 3. Add `action_updates` method to `NixStore` (alongside `action_apply`)

```python
def action_updates(self) -> None:
    if not self.on_main_screen():
        return
    def done(succeeded: bool | None) -> None:
        self.active_input().focus()
    self.push_screen(UpdateScreen(), done)
```
