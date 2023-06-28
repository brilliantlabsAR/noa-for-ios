import bluetooth
import time
import urandom


def choices(rng, k=1):
    l = []
    for _ in range(k):
        l.append(urandom.choice(rng))
    return l


while True:
    if bluetooth.connected():
        mtu = bluetooth.max_length()
        start = time.ticks_ms()
        i = 0
        while i < 20:
            try:
                bluetooth.send(bytearray(choices(range(0, 256), k=mtu)))
                i += 1
            except OSError:
                pass
        end = time.ticks_ms()
        diff = time.ticks_diff(end, start)
        sent = (i - 1) * mtu
        print(f"Sent {sent} bytes at {round(sent/diff, 2)}kB/s")
