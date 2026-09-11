"""Tiny launch window: update automatically, then play. No admin privileges needed."""
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import messagebox
import updater


def main():
    root = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'PulseFour' / 'app'
    root.mkdir(parents=True, exist_ok=True)
    # Windows releases use a byte-range lock; the OS releases it even after a crash.
    import msvcrt
    lock = (root / 'launcher.lock').open('a+b')
    lock.seek(0)
    lock.write(b'0')
    lock.flush()
    lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        lock.close()
        return
    window = tk.Tk()
    window.title('Pulse Four')
    window.geometry('390x130')
    window.resizable(False, False)
    window.configure(bg='#11152a')
    label = tk.Label(window, text='Checking for updates…', bg='#11152a', fg='#58f0ea', font=('Segoe UI', 12))
    label.pack(expand=True)
    events = queue.Queue()
    closing = [False]
    # Closing during a download cancels this launch; installation remains transactional.
    def close():
        closing[0] = True
        window.destroy()
    window.protocol('WM_DELETE_WINDOW', close)

    def work():
        try:
            folder = updater.check_update(root, lambda text: events.put(('status', text)))
            if folder is None:
                raise RuntimeError('No Windows release is published yet.')
            events.put(('launch', folder))
        except Exception as error:
            (root / 'update-error.log').write_text(str(error), encoding='utf-8')
            _, folder = updater.active(root)
            events.put(('launch', folder) if folder else ('error', str(error)))

    def poll():
        try:
            while True:
                kind, value = events.get_nowait()
                if kind == 'status':
                    label.config(text=value)
                elif kind == 'launch':
                    try:
                        subprocess.Popen([str(value / 'PulseFour.exe'), *sys.argv[1:]], cwd=value)
                    except OSError as error:
                        messagebox.showerror('Pulse Four', str(error))
                    close()
                    return
                else:
                    messagebox.showerror('Pulse Four', 'Could not install the game. Check your connection and try again.\n\n' + value)
                    close()
                    return
        except queue.Empty:
            pass
        window.after(80, poll)
    threading.Thread(target=work, daemon=True).start()
    window.after(80, poll)
    window.mainloop()
    # Do not release the lock while the worker may still be installing an update.
    # Process exit terminates the daemon; current.txt only changes after verification.
    os._exit(0)

if __name__ == '__main__':
    main()
