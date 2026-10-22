#!/usr/bin/env python3
"""Check that pod-attach holds Herdr until kubectl applies the terminal size."""

import fcntl
import os
import pty
import select
import struct
import subprocess
import termios
import time


def set_size(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def read_until_exit(fd, proc, timeout):
    output = b""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                output += os.read(fd, 4096)
            except OSError:
                break
        if proc.poll() is not None and not ready:
            break
    return output


def check_waits_for_size():
    # A kubectl exec PTY starts at 0x0 and receives the client size afterwards.
    master, slave = pty.openpty()
    set_size(master, 0, 0)
    proc = subprocess.Popen(
        ["pod-attach", "--version"], stdin=slave, stdout=slave, stderr=slave
    )
    os.close(slave)
    early = read_until_exit(master, proc, 0.5)
    assert proc.poll() is None and b"herdr" not in early, early
    set_size(master, 24, 80)
    output = read_until_exit(master, proc, 5)
    assert proc.wait(timeout=5) == 0, output
    assert b"herdr " in output, output
    os.close(master)


def check_skips_without_terminal():
    start = time.monotonic()
    result = subprocess.run(
        ["pod-attach", "--version"],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        check=True,
    )
    assert result.stdout.startswith(b"herdr "), result
    assert time.monotonic() - start < 2


def main():
    check_waits_for_size()
    check_skips_without_terminal()
    print("pod-attach waits for a terminal size and execs Herdr")


if __name__ == "__main__":
    main()
