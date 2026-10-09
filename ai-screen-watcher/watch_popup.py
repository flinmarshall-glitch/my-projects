#!/usr/bin/env python3
import sys, tkinter as tk

WIDTH = 520
text = " ".join(sys.argv[1:]) or "(empty message)"

root = tk.Tk()
root.title("Desktop check")
root.attributes("-topmost", True)
sw, sh = root.winfo_screenwidth(), root.winfo_screenheight()
root.geometry(f"{WIDTH}x{sh}+{sw - WIDTH}+0")
root.configure(bg="#232629")

close = lambda *_: root.destroy()
root.bind("<Escape>", close)
root.bind("<Button-3>", close)       # right-click anywhere
root.protocol("WM_DELETE_WINDOW", close)

tk.Button(root, text="✕ Close", command=close, bg="#31363b", fg="white",
          relief="flat", padx=12, pady=6).pack(anchor="ne", padx=10, pady=10)

frame = tk.Frame(root, bg="#232629")
frame.pack(fill="both", expand=True, padx=(20, 10), pady=(0, 20))
bar = tk.Scrollbar(frame)
bar.pack(side="right", fill="y")
box = tk.Text(frame, bg="#232629", fg="white", font=("DejaVu Sans", 12),
              wrap="word", relief="flat", borderwidth=0, highlightthickness=0,
              yscrollcommand=bar.set, spacing3=6)
box.pack(side="left", fill="both", expand=True)
bar.config(command=box.yview)
box.insert("1.0", text)
box.config(state="disabled")

root.mainloop()
