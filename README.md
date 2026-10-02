# steam-download-uncap

Removes the socket-buffer ceilings on Steam transfers — receiving and sending
LAN transfers between two machines, and CDN downloads over a fast internet link
alike.

If Steam downloads or LAN transfers sit well below what the rest of your network
does, install this and restart Steam.

## Install

Tested on SteamOS only. See [Other distributions](#other-distributions) before
installing elsewhere.

On a Steam Deck this happens in Desktop Mode: hold the power button, choose
*Switch to Desktop*. Open a terminal — the *Konsole* icon in the taskbar — and
run:

    cd ~
    git clone https://github.com/lonsdaleite/steam-download-uncap
    cd ~/steam-download-uncap
    ./install.sh
    systemctl --user restart steam-launcher.service

The first run builds the library in a container and takes a minute or two.
No sudo, no writes outside `$HOME`, nothing in the read-only rootfs.
`install.sh` calls `build.sh` when `build/` is empty.

Steam restarts on the last command; a reboot or a round trip through Game Mode
does the same thing.

Start a download and watch the speed. To confirm the shim is loaded rather than
guessing from the number:

    grep -c norcvbuf /proc/$(pgrep -x steam | head -1)/maps

Anything above `0` means it is in. A `0` means Steam was not restarted, or is
not started by `steam-launcher.service`.

## Uninstall

    cd ~/steam-download-uncap
    ./uninstall.sh
    systemctl --user restart steam-launcher.service

## Other distributions

Two things this depends on are SteamOS-specific, so Bazzite, CachyOS, Arch and
the rest may need adjusting:

- The `LD_PRELOAD` is delivered through a drop-in for the `steam-launcher.service`
  user unit. Where Steam is started from a desktop entry instead, the drop-in
  attaches to nothing and the shim never loads. Check with
  `systemctl --user list-unit-files 'steam*'`.
- `build.sh` needs `podman`, because SteamOS ships no compiler. With `gcc` and
  32-bit headers present, build `src/norcvbuf.c` directly — see the two `gcc`
  lines in `build.sh`.

Reports from other distributions are welcome.

## Why

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

The sending side of a LAN transfer has the same problem with the other buffer:
the client sets `SO_SNDBUF` so small that the kernel clamps it to its minimum of
4608 bytes. The socket drains faster than Steam can refill a buffer that size,
so the connection spends its time application-limited with a fraction of the
congestion window in flight.

This shim interposes `setsockopt` and drops `SO_RCVBUF` and `SO_SNDBUF`,
reporting success. Steam believes it configured the socket; the kernel keeps
autotuning it.

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

The same handheld sending a LAN transfer to a PC over Wi-Fi 6, before and
after `SO_SNDBUF` was added to the shim. The before figure is
application-limited; the after figure is bound by the air link, with RTT
growing from about 1.3 ms to 12–19 ms as the queue fills.

| | before | after |
| --- | --- | --- |
| throughput | 31 MB/s | 70 MB/s |
| `tb` | 4608 | 4194304 |

Socket figures come from `ss -tinm state established dst <peer>`, with `<peer>`
the other machine on a LAN transfer or the CDN host on a download.

## Layout

    src/norcvbuf.c   the interposer, named after the option it first swallowed
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
process under Steam can size its own receive or send buffer any more — the kernel
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
