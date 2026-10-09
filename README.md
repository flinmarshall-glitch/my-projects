# Screenwatcher

Takes a screenshot of your desktop every minute and has Claude describe it, building a simple, searchable text log of your day.

Built for Linux with KDE Plasma. No video recording, no database, just plain-text logs you can `grep`.

---

## How it works

1. Every minute, a systemd user timer runs `screenwatcher.sh`.
2. The script grabs a full-screen screenshot with Spectacle.
3. The image is sent to the Claude API with a short prompt asking what's on screen.
4. Claude's description is appended to a daily log with a timestamp.
5. The screenshot is deleted (or kept, if you turn that on).

Example log line:

```
2026-10-09 10:14  Editing README.md in Kate; Firefox open in the background on a KDE Plasma settings page.
```

---

## Requirements

- Linux with KDE Plasma (uses `spectacle` for screenshots)
- `bash`, `curl`, `jq`, `base64`
- An Anthropic API key

```bash
sudo apt install spectacle curl jq    # Debian/Ubuntu
sudo pacman -S spectacle curl jq      # Arch
```

---

## Setup

```bash
# 1. Put the script somewhere on your PATH
mkdir -p ~/.local/bin
cp screenwatcher.sh ~/.local/bin/
chmod +x ~/.local/bin/screenwatcher.sh

# 2. Store your API key (readable only by you)
mkdir -p ~/.config/screenwatcher
echo 'ANTHROPIC_API_KEY=sk-ant-...' > ~/.config/screenwatcher/env
chmod 600 ~/.config/screenwatcher/env

# 3. Install the systemd user service + timer
cp screenwatcher.service screenwatcher.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now screenwatcher.timer
```

---

## Where things live

| Path | What's there |
|---|---|
| `~/.local/bin/screenwatcher.sh` | The script |
| `~/.config/screenwatcher/env` | API key and settings |
| `~/.local/share/screenwatcher/logs/YYYY-MM-DD.log` | One log file per day |
| `~/.local/share/screenwatcher/shots/` | Screenshots (only if `KEEP_SHOTS=1`) |

---

## Configuration

Set these in `~/.config/screenwatcher/env`:

| Variable | Default | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | (required) | Your API key |
| `SW_MODEL` | `claude-haiku-5-5` | Model used for descriptions |
| `KEEP_SHOTS` | `0` | Set to `1` to keep screenshots instead of deleting them |
| `SW_PROMPT` | "Describe what's on this screen in one sentence." | Prompt sent with each screenshot |

To change the interval, edit `OnCalendar=` / `OnUnitActiveSec=` in `screenwatcher.timer`, then run `systemctl --user daemon-reload`.

---

## Aliases

Add these to your `~/.bashrc` or `~/.zshrc`, then run `source ~/.bashrc`:

```bash
# --- Screenwatcher ---
SW_LOGS="$HOME/.local/share/screenwatcher/logs"

# Control
alias sw-start='systemctl --user start screenwatcher.timer'
alias sw-stop='systemctl --user stop screenwatcher.timer'
alias sw-status='systemctl --user status screenwatcher.timer'
alias sw-now='~/.local/bin/screenwatcher.sh'          # take one shot right now

# Reading logs
alias sw-today='less "$SW_LOGS/$(date +%F).log"'
alias sw-yesterday='less "$SW_LOGS/$(date -d yesterday +%F).log"'
alias sw-tail='tail -f "$SW_LOGS/$(date +%F).log"'    # watch live
alias sw-logs='cd "$SW_LOGS"'

# Search all logs: sw-search firefox
sw-search() { grep -ri --color=auto "$*" "$SW_LOGS"; }

# Pause for a while, then resume automatically: sw-pause 30  (minutes)
sw-pause() {
  systemctl --user stop screenwatcher.timer
  echo "Screenwatcher paused for ${1:-15} min"
  (sleep "$(( ${1:-15} * 60 ))" && systemctl --user start screenwatcher.timer) &>/dev/null &
  disown
}
```

| Alias | What it does |
|---|---|
| `sw-start` / `sw-stop` | Start or stop the minute-by-minute capture |
| `sw-status` | Check whether the timer is running |
| `sw-now` | Capture and describe the screen once, immediately |
| `sw-today` / `sw-yesterday` | Open that day's log |
| `sw-tail` | Watch today's log update live |
| `sw-search <text>` | Search every log for a word or phrase |
| `sw-pause [min]` | Pause capture (default 15 min), then resume on its own |
| `sw-logs` | Jump to the logs folder |

---

## Privacy notes

- Every screenshot is sent to the Anthropic API. Anything on screen (passwords, messages, banking) goes with it. Use `sw-pause` or `sw-stop` before sensitive work.
- Screenshots are deleted after each run unless `KEEP_SHOTS=1`.
- Logs are plain text in your home folder; protect them like any other personal file.

---

## Cost

One image per minute adds up: roughly 480 calls in an 8-hour day. A small, fast model keeps this cheap; check current API pricing before leaving it running all day.

---

## Uninstall

```bash
systemctl --user disable --now screenwatcher.timer
rm ~/.config/systemd/user/screenwatcher.{service,timer}
rm ~/.local/bin/screenwatcher.sh
rm -r ~/.config/screenwatcher ~/.local/share/screenwatcher   # deletes all logs
```
Then remove the alias block from your shell config.
