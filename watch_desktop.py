#!/usr/bin/env python3
import subprocess, os, sys, time
from PIL import Image, ImageChops, ImageStat

INTERVAL = 60
THRESHOLD = 2.0
POPUP_WIDTH = 520     # must match WIDTH in watch_popup.py
PROMPT = ("Read the image file shot.jpg, which is a screenshot of my desktop. "
          "Write a useful, detailed response in plain text with no markdown symbols "
          "(no #, *, or backticks). Use these sections: "
          "WHAT I'M DOING: two or three sentences on what is on screen and what I seem to be working on. "
          "SUGGESTIONS: four to six specific, actionable suggestions based on what you see, such as next steps, "
          "mistakes or problems you notice, faster ways to do it, or tools and shortcuts that would help. "
          "HEADS UP: anything that looks off, risky, or worth double-checking, or say nothing notable. "
          "Be concrete and refer to what is actually visible rather than giving generic advice.")
WORKDIR = os.path.expanduser("~/.desktop_watch")
SHOT = os.path.join(WORKDIR, "shot.jpg")
RAW = os.path.join(WORKDIR, "raw.png")
LOG = os.path.expanduser("~/desktop_watch.log")
POPUP = os.path.expanduser("~/bin/watch_popup.py")
CLAUDE = os.path.expanduser("~/.npm-global/bin/claude")
os.makedirs(WORKDIR, exist_ok=True)

# Make sure Claude Code uses your login, not an API key
env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
popup = None
last_small = None

def log(msg):
    with open(LOG, "a") as f:
        f.write(f"[{time.strftime('%F %T')}] {msg}\n\n")

def take_screenshot():
    """Returns a small grayscale thumbnail used only for change detection."""
    subprocess.run(["spectacle", "-b", "-n", "-f", "-o", RAW],
                   check=True, stderr=subprocess.DEVNULL)
    img = Image.open(RAW).convert("RGB")
    # Ignore the popup's strip on the right edge so the popup itself
    # (or closing it) doesn't count as a screen change
    cropped = img.crop((0, 0, max(1, img.width - POPUP_WIDTH), img.height))
    small = cropped.convert("L").resize((96, 54))
    img.thumbnail((1280, 1280))
    img.save(SHOT, "JPEG", quality=80)
    return small

while True:
    try:
        small = take_screenshot()
        diff = None
        if last_small is not None:
            diff = ImageStat.Stat(ImageChops.difference(small, last_small)).mean[0]

        if diff is not None and diff < THRESHOLD:
            log(f"skipped, screen unchanged (diff={diff:.2f})")
        else:
            last_small = small
            result = subprocess.run(
                [CLAUDE, "-p", PROMPT, "--allowedTools", "Read"],
                capture_output=True, text=True, timeout=300,
                cwd=WORKDIR, env=env)
            text = result.stdout.strip() or f"(no output) {result.stderr.strip()}"
            log(text)
            if popup and popup.poll() is None:
                popup.terminate()
            popup = subprocess.Popen([sys.executable, POPUP, text])
    except Exception as e:
        log(f"error: {e}")
    time.sleep(INTERVAL)
