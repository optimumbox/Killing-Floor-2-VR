"""Steam launch wrapper for the KF2VR Workshop item.

Set as the game's Steam Launch Options:
    "<this folder>\\Play.cmd" %command%
Steam then starts this instead of KF2 and passes the normal game command.
"Play normally" runs that command untouched (nothing is injected). "Play in
VR" mirrors this read-only Workshop copy into %LOCALAPPDATA%\\KF2VR\\Workshop
(only changed files are copied; settings and sessions there are kept) and
opens the KF2-VR launcher from that writable copy.
"""
import ctypes
import os
import subprocess
import sys
import tkinter as tk
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCAL = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "KF2VR" / "Workshop" / "KF2VR"
# The prototype's copy (same files, its settings and sessions) moves over once.
OLD_LOCAL = LOCAL.parent.parent / "WorkshopPrototype" / "KF2VR"
# Per-user files the local copy keeps across updates (never shipped).
KEEP_DIRS = ["sessions", "logs", "__pycache__", "build"]  # build: SteamCMD and server install logs
KEEP_FILES = ["settings.json", "JOIN-SERVER.txt", "*.pyc"]
NO_WINDOW = 0x08000000
# The mod's game packages live once, in the item's BrewedPC folder, where plain
# Killing Floor 2 also loads them (desktop players joining from the server
# browser). The launcher's copy gets them in its Packages folder.
BREWED = HERE.parent / "BrewedPC"
GAME_PACKAGES = {"Script": ["KF2VR.u", "KF2VRNet.u", "KF2VRNetClient.u"], "Packages": ["KF2VRHands.upk"]}
SHARED = [name for names in GAME_PACKAGES.values() for name in names]


def mirror():
    if OLD_LOCAL.exists() and not LOCAL.exists():
        LOCAL.parent.mkdir(parents=True, exist_ok=True)
        OLD_LOCAL.rename(LOCAL)
    LOCAL.mkdir(parents=True, exist_ok=True)
    # Robocopy never purges excluded names, so the user's files and the game
    # packages (copied from BrewedPC next) survive /MIR.
    jobs = [[str(HERE / "app"), str(LOCAL / "app"), "/MIR", "/XD", *KEEP_DIRS, "/XF", *KEEP_FILES, *SHARED]]
    jobs += [[str(BREWED / folder), str(LOCAL / "app" / "Packages"), *names] for folder, names in GAME_PACKAGES.items()]
    for job in jobs:
        result = subprocess.run(["robocopy", *job, "/NJH", "/NJS", "/NP", "/R:2", "/W:1"],
                                creationflags=NO_WINDOW, capture_output=True, text=True)
        if result.returncode >= 8:
            raise RuntimeError("Could not copy KF2-VR to " + str(LOCAL) + "\n" + result.stdout[-1500:])
    for names in GAME_PACKAGES.values():
        for name in names:
            if not (LOCAL / "app" / "Packages" / name).exists():
                raise RuntimeError("KF2VR is missing " + name + ". Let Steam finish updating KF2VR, then try again.")
    for name in ("READ ME FIRST.txt", "Start KF2-VR.cmd"):
        source = HERE / name
        if source.exists():
            (LOCAL / name).write_bytes(source.read_bytes())


def play_vr(window, status):
    status.set("Updating the local KF2-VR copy...")
    window.update()
    try:
        mirror()
    except Exception as error:  # Shown to the player; nothing else to clean up.
        status.set(str(error))
        return
    app = LOCAL / "app"
    # Let the launcher take the foreground when its window opens (Windows
    # otherwise opens it behind whatever had focus).
    ctypes.windll.user32.AllowSetForegroundWindow(-1)
    subprocess.Popen([str(app / "runtime" / "pythonw.exe"), str(app / "tools" / "multiplayer" / "launcher_gui.py")],
                     cwd=str(app))
    window.destroy()


def play_normal(window, status):
    command = sys.argv[1:]
    if not command:
        status.set("Start this from Steam (Launch Options) to play normally.")
        return
    subprocess.Popen(command, cwd=str(Path(command[0]).parent))
    window.destroy()


def main():
    window = tk.Tk()
    window.title("Killing Floor 2")
    window.configure(bg="#111111")
    window.resizable(False, False)
    status = tk.StringVar(value="")
    tk.Label(window, text="How do you want to play?", fg="#eeeeee", bg="#111111",
             font=("Segoe UI", 14, "bold")).pack(padx=30, pady=(24, 14))
    style = {"font": ("Segoe UI", 12), "width": 22, "pady": 8, "relief": "flat", "cursor": "hand2"}
    vr = tk.Button(window, text="Play in VR (KF2-VR)", bg="#8a1c1c", fg="white", activebackground="#a82424",
                   command=lambda: play_vr(window, status), **style)
    vr.pack(padx=30, pady=5)
    tk.Button(window, text="Play normally", bg="#333333", fg="white", activebackground="#444444",
              command=lambda: play_normal(window, status), **style).pack(padx=30, pady=5)
    tk.Label(window, textvariable=status, fg="#bbbbbb", bg="#111111", wraplength=320,
             font=("Segoe UI", 9)).pack(padx=30, pady=(10, 18))
    window.bind("<Escape>", lambda event: window.destroy())
    window.bind("<Return>", lambda event: play_vr(window, status))
    vr.focus_set()
    window.update_idletasks()
    x = (window.winfo_screenwidth() - window.winfo_width()) // 2
    y = (window.winfo_screenheight() - window.winfo_height()) // 3
    window.geometry(f"+{x}+{y}")
    window.attributes("-topmost", True)
    window.mainloop()


if __name__ == "__main__":
    main()
