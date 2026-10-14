#!/usr/bin/env python3
"""Bridge an evdev device to local UDP for Godot.

Usage: python3 evdev_udp_bridge.py /dev/input/eventNN PORT

Reads raw input_event bytes and forwards them as UDP datagrams to
127.0.0.1:PORT. Sends a HELLO datagram on start so the game can confirm
the bridge is alive. Exits silently when orphaned (parent gone).
"""
import os
import socket
import sys


def main() -> None:
    dev, port = sys.argv[1], int(sys.argv[2])
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    fd = os.open(dev, os.O_RDONLY)
    sock.sendto(b"HELLO", ("127.0.0.1", port))
    try:
        while True:
            if os.getppid() == 1:  # orphaned: the game died without close()
                return
            data = os.read(fd, 4096)
            if not data:
                return
            sock.sendto(data, ("127.0.0.1", port))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
