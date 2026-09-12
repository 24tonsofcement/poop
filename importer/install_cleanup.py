"""Remove only obsolete managed installs after the current game has started."""
import os
from pathlib import Path
import re
import shutil


def running_images():
    if os.name != 'nt': return []
    import ctypes
    from ctypes import wintypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    psapi = ctypes.WinDLL('psapi', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    ids = (wintypes.DWORD * 65536)(); used = wintypes.DWORD()
    if not psapi.EnumProcesses(ids, ctypes.sizeof(ids), ctypes.byref(used)):
        raise OSError('Cannot inspect running versions')
    paths = []
    for pid in ids[:used.value // ctypes.sizeof(wintypes.DWORD)]:
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle: continue
        try:
            size = wintypes.DWORD(32768); buffer = ctypes.create_unicode_buffer(size.value)
            if kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
                paths.append(Path(buffer.value).resolve())
        finally:
            kernel.CloseHandle(handle)
    return paths


def cleanup(root, current_folder, images=None):
    root = Path(root).resolve(); current_folder = Path(current_folder).resolve()
    current = (root/'current.txt').read_text().strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', current): return []
    versions = root/'versions'
    if current_folder != (versions/current).resolve(): return []
    if not (current_folder/'PulseFour.exe').is_file(): return []
    images = running_images() if images is None else [Path(p).resolve() for p in images]
    removed = []
    current_number = tuple(map(int, current.split('.')))
    for folder in versions.iterdir():
        if not re.fullmatch(r'\d+\.\d+\.\d+', folder.name): continue
        if tuple(map(int, folder.name.split('.'))) >= current_number: continue
        # Do not follow links/junctions outside the managed versions directory.
        if folder.is_symlink() or folder.resolve().parent != versions.resolve(): continue
        if any(image.is_relative_to(folder.resolve()) for image in images): continue
        if not folder.is_dir(): continue
        try:
            shutil.rmtree(folder)
            removed.append(folder.name)
        except OSError:
            pass  # Locked leftovers are retried on the next successful launch.
    return removed


def cleanup_installed(current_folder):
    local = os.environ.get('LOCALAPPDATA')
    if not local: return
    root = Path(local)/'PulseFour'/'app'
    try:
        cleanup(root, current_folder)
    except (OSError, ValueError):
        pass  # Cleanup must never prevent play or touch an unmanaged install.
