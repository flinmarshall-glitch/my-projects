# AI Screen Watcher (Claude Code version)

A small Linux (KDE Plasma) tool that periodically takes a silent screenshot of your desktop, has Claude describe it through the Claude Code CLI, and shows the answer in a full-height popup on the right edge of your screen.

It only calls Claude when something on screen has actually changed, so idle time costs nothing.

## Features

- Silent screenshots via Spectacle
- Uses your Claude login through `claude -p`, with no API key
- Skips the Claude call when the screen hasn't changed (local image comparison)
- 20 switchable prompts (focus, coach, debug, code-review, writing, and more)
- Scrollable, full-height popup that stays until you close it
- Log of every response

## Requirements

- Linux with KDE Plasma and Spectacle
- Python 3 with `venv` and `python3-tk`
- [Claude Code](https://docs.claude.com) installed and logged in (`claude`)

## Install

```bash
sudo apt install python3-venv python3-pip python3-tk
python3 -m venv ~/watch-venv
~/watch-venv/bin/pip install pillow

mkdir -p ~/bin
cp watch_desktop.py watch_popup.py ~/bin/
cp -r prompts ~/bin/
mkdir -p ~/.desktop_watch
cp prompts/default.txt ~/.desktop_watch/prompt.txt
```

`watch_desktop.py` calls Claude Code by full path (`~/.npm-global/bin/claude`). Change the `CLAUDE` line if `which claude` shows a different location.

Add these to `~/.bashrc`, then run `source ~/.bashrc`:

```bash
alias watch-start='nohup ~/watch-venv/bin/python ~/bin/watch_desktop.py > /dev/null 2>&1 &'
alias watch-stop='pkill -f watch_desktop.py'
alias watch-log='tail -f ~/desktop_watch.log'
alias watch-last='~/watch-venv/bin/python ~/bin/watch_popup.py "$(cat ~/.desktop_watch/last.txt)" &'
alias watch-close='pkill -f watch_popup.py'
watch-prompt() {
  if [ -z "$1" ] || [ ! -f ~/bin/prompts/$1.txt ]; then
    echo "Options: $(ls ~/bin/prompts | sed 's/\.txt//' | tr '\n' ' ')"; return
  fi
  cp ~/bin/prompts/$1.txt ~/.desktop_watch/prompt.txt && echo "Prompt set to: $1"
}
```

## Usage

| Command | What it does |
|---|---|
| `watch-start` | Start in the background |
| `watch-stop` | Stop it |
| `watch-log` | Follow the log live |
| `watch-last` | Reopen the latest response |
| `watch-close` | Close the popup |
| `watch-prompt NAME` | Switch prompt (no name lists them) |

A new prompt applies at the next real check. If the screen hasn't changed, that check is skipped.

## Prompts

`default` (a copy of `focus`), `coach`, `debug`, `focus`, `glance`, `writing`, `study`, `research`, `email`, `code-review`, `design`, `security`, `timelog`, `standup`, `explain`, `shortcuts`, `spreadsheet`, `shopping`, `planner`, `translate`.

Each is a plain text file in `prompts/`. Edit one, then run `watch-prompt NAME` to apply it.

## Configuration

Edit the constants at the top of `watch_desktop.py` and restart:

| Setting | Meaning |
|---|---|
| `INTERVAL` | Seconds between screen comparisons |
| `THRESHOLD` | Screen-change sensitivity (0 to 255). Lower catches smaller changes |
| `POPUP_WIDTH` | Must match `WIDTH` in `watch_popup.py` |

## Usage limits

Each real check counts against your Claude plan's usage limits, and each one is heavier than a plain API call. Keep `INTERVAL` long and leave "usage credits" off so nothing beyond plan limits can be charged. Billing behavior for scripted `claude -p` use has varied, so check your usage pages after a few runs.

## Privacy

Each check captures your **entire screen**, including anything private, and sends it to Anthropic. Run `watch-stop` before opening anything sensitive. Screenshots are saved to `~/.desktop_watch/` and overwritten on each check, and responses are appended to `~/desktop_watch.log`.

## Popup focus

The popup must not steal focus while you type. Add a KDE window rule: System Settings, Window Management, Window Rules, match window title `Desktop check`, and set Focus stealing prevention to Force, Extreme. Don't use a "notification" window type, since it makes the popup unclickable.

## License

Add a license of your choice (for example MIT).
