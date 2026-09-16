#!/usr/bin/env python3
"""Stdlib-only evdev key reader. One thread per keyboard, zero idle CPU.

Protocol (stdout, parsed by KeyMonitor.qml SplitParser):
  P <code>  press
  R <code>  release
  DEV <n>   device count (always on first scan, then on change)

Filters: EV_KEY only, code < 0x100, value 0/1 only (drop autorepeat=2).
Needs read access to /dev/input/event*. The plugin obtains it with a
one-click pkexec grant (udev rule + ACL, no logout). Without access the
script watches zero devices and reports DEV 0.
"""

import contextlib
import fcntl
import glob
import os
import queue
import struct
import sys
import threading

_WATCHED_LOCK = threading.Lock()

EV_KEY = 1
EVENT = struct.Struct("@llHHi")
READ_CHUNK = EVENT.size * 32
DEVICES_GLOB = "/dev/input/event*"
RESCAN_INTERVAL = 5.0
TYPE_BITS_REQUEST = (2 << 30) | (8 << 16) | (0x45 << 8) | 0x20
TYPE_BITS = struct.Struct("<Q")


def has_key_events(path):
    try:
        with open(path, "rb", buffering=0) as fd:
            bitmap = fcntl.ioctl(fd, TYPE_BITS_REQUEST, b"\x00" * 8)
        return (TYPE_BITS.unpack(bitmap)[0] >> EV_KEY) & 1 == 1
    except (OSError, ValueError):
        return False


def watch_device(path, q, watched):
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    with _WATCHED_LOCK:
        watched.add(path)
    buf = b""
    try:
        while True:
            try:
                data = os.read(fd, READ_CHUNK)
            except OSError:
                break
            if not data:
                break
            buf += data
            # Partial read guard: os.read can split mid-event.
            # Old code iter_unpack'd raw chunk -> struct.error crash (DoS).
            n = (len(buf) // EVENT.size) * EVENT.size
            chunk, buf = buf[:n], buf[n:]
            if len(buf) > EVENT.size * 4:
                buf = b""  # resync, never grow unbounded
            for _ts, _tus, etype, code, value in EVENT.iter_unpack(chunk):
                if etype != EV_KEY or code >= 0x100:
                    continue
                if value == 1:
                    _emit(q, "P", code)
                elif value == 0:
                    _emit(q, "R", code)
    finally:
        with contextlib.suppress(OSError):
            os.close(fd)
        with _WATCHED_LOCK:
            watched.discard(path)


def _emit(q, kind, code):
    # Bounded queue: rogue device flood must not OOM the shell.
    # Drop oldest, keep newest (live keys matter, backlog does not).
    try:
        q.put_nowait((kind, code))
    except queue.Full:
        with contextlib.suppress(queue.Empty):
            q.get_nowait()
        with contextlib.suppress(queue.Full):
            q.put_nowait((kind, code))


def scan(q, watched):
    with _WATCHED_LOCK:
        known = set(watched)
    for path in glob.glob(DEVICES_GLOB):
        if path in known:
            continue
        try:
            if not os.access(path, os.R_OK) or not has_key_events(path):
                continue
        except OSError:
            continue
        t = threading.Thread(target=watch_device, args=(path, q, watched), daemon=True)
        t.start()


_first_scan = True


def rescan_loop(q, watched):
    # Single daemon thread, no Timer-chain pileup. Sleep first so the
    # first DEV line is always emitted synchronously from main().
    global _first_scan
    import time

    while True:
        time.sleep(0 if _first_scan else RESCAN_INTERVAL)
        with _WATCHED_LOCK:
            before = len(watched)
        with contextlib.suppress(Exception):
            scan(q, watched)
        with _WATCHED_LOCK:
            after = len(watched)
        if _first_scan or after != before:
            print(f"DEV {after}", flush=True)
            _first_scan = False


def main():
    q = queue.Queue(maxsize=256)
    watched = set()
    t = threading.Thread(target=rescan_loop, args=(q, watched), daemon=True)
    t.start()
    while True:
        kind, code = q.get()
        sys.stdout.write(f"{kind} {code}\n")
        sys.stdout.flush()


if __name__ == "__main__":
    with contextlib.suppress(KeyboardInterrupt):
        main()
