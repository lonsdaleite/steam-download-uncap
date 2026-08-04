# steam-download-uncap

Removes the receive-window ceiling on Steam downloads — LAN transfers between
two machines, and CDN downloads over a fast internet link alike.

The Steam client calls `setsockopt(SO_RCVBUF)` with 128 KiB on its download
sockets. An explicit `SO_RCVBUF` switches off Linux receive-buffer autotuning
and pins the window scale factor negotiated in the SYN, so the advertised
receive window can never grow afterwards. A receive window is the number of
bytes a sender may keep in flight before an acknowledgement returns, which puts
a hard bound on throughput:

    throughput = window / RTT

Bandwidth does not appear in that formula. A 128 KiB window sustains roughly
58 MB/s at 2.9 ms RTT and about 13 MB/s at 10 ms, no matter how fast the link
underneath is. This is why the ceiling shows up first on Wi-Fi and on distant
CDNs: both raise RTT, while a short wired hop hides the problem.

This shim interposes `setsockopt` and drops `SO_RCVBUF`, reporting success.
Steam believes it configured the socket; the kernel keeps autotuning it.

## Measured

A 2.5 GbE PC feeding a Wi-Fi 6E handheld over Steam's LAN transfer. Nothing was
saturated at the low figure: both CPUs sat near 16 %, both NVMe drives were over
90 % idle, and a second stream pushed in parallel raised the total to 141 MB/s,
so the air link still had headroom. `scp` across the same path ran at 175 MB/s
because it never sets `SO_RCVBUF`.

| | before | after |
| --- | --- | --- |
| throughput | 65 MB/s | 160 MB/s |
| `rb` | 262144 | 33554432 |
| `rcv_wnd` | 171536 | 22671360 |
| `rcv_wscale` | 2 | 10 |

## Install

    ./install.sh
    systemctl --user restart steam-launcher.service

No sudo, no writes outside `$HOME`, nothing in the read-only rootfs.
`install.sh` calls `build.sh` when `build/` is empty.

Verify after restarting Steam and starting a download:

    PID=$(pgrep -x steam | head -1)
    grep norcvbuf /proc/$PID/maps
    ss -tinm state established dst <peer-ip>

`rb` should read tens of megabytes instead of `rb262144`.

## Uninstall

    ./uninstall.sh
    systemctl --user restart steam-launcher.service

## Layout

    src/norcvbuf.c   the interposer, named after the option it swallows
    build.sh         builds both ELF classes in a throwaway podman container
    install.sh       installs the libraries and the systemd user drop-in
    uninstall.sh     reverses install.sh

`build/` is generated and untracked.

## Why a user-level systemd drop-in

`~/.local/share/Steam/steam.sh` is a tempting place for the `LD_PRELOAD` export
and does work, but the Steam client restores that file from its own bootstrap on
startup, silently dropping the change. The client is launched by the
`steam-launcher.service` user unit, so a drop-in under `~/.config/systemd/user/`
sets the variable from outside Steam's reach and needs no root. Living in
`/home` also means SteamOS atomic updates leave it alone, with none of the
`/etc/atomic-update.conf.d/` bookkeeping a system-level daemon requires.

## Side effects

`LD_PRELOAD` is inherited by every Steam child process, games included, so no
process under Steam can size its own receive buffer any more — the kernel
decides instead. That is the normal path for most software, but it is the first
thing to revert if network behaviour anywhere under Steam looks strange.

Steam's stderr gains one line per process:

    ERROR: ld.so: object '.../libnorcvbuf.so' from LD_PRELOAD cannot be
    preloaded (wrong ELF class: ELFCLASS32): ignored.

The Steam client is 32-bit while its children are mixed, and glibc does not
expand `$LIB` inside `LD_PRELOAD`, so both builds are listed and the loader
skips the one that does not match. Expected, harmless.

## Tested and irrelevant

Wi-Fi power save, CPU frequency and TDP limits, `net.ipv4.tcp_adv_win_scale`,
and `net.core.rmem_max` all leave the speed unchanged. The kernel ceiling in
particular never binds: Steam asks for 128 KiB, well under the default
`rmem_max` of 208 KiB, so raising it changes nothing.
