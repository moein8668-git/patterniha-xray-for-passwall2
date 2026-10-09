# patterniha's Xray for PassWall2 (OpenWrt)

[English](README.md) | [فارسی](README.fa.md)

## ❤️ Special thanks to patterniha

**All credit goes to [patterniha](https://github.com/patterniha), the creator of this core.**
He builds and maintains the custom Xray core ([patterniha/xray-core](https://github.com/patterniha/xray-core)) and the clients
that use it: [PattN](https://github.com/patterniha/PattN) (desktop) and [PattNG](https://github.com/patterniha/PattNG) (Android).
This repository contains **none of his code**: it is only a small installer that downloads his official release and runs it on OpenWrt.
Please support and star his projects.

> ⚠️ **This script is 100% vibe-coded** (written with an AI assistant). It was tested on one x86_64 OpenWrt 25.12 VM only.
> Read it before running it as root, and use it at your own risk.

## What it is

Not a rewrite of Xray. `pattx` is a ~200-line shell script that:

- detects your router architecture (x86, arm, mips, mipsel, riscv64, loong64, ...),
- downloads the matching official release from `patterniha/xray-core` and verifies its SHA-256,
- installs it to `/opt/pattx` with a procd service (autostart + respawn),
- optionally makes **PassWall2** use this core instead of the stock `xray`,
- updates / rolls back with one command.

The core is the same one used by PattN and PattNG, so the extra features he adds to his core are available on your router
through the normal Xray JSON config.

## Install

On the router (needs internet access to GitHub; `curl` or `wget`; `unzip` is installed automatically if missing):

```sh
wget -O /tmp/pattx.sh https://raw.githubusercontent.com/moein8668-git/patterniha-xray-for-passwall2/main/pattx.sh
sh /tmp/pattx.sh install
```

Or from Windows (router reachable by SSH with root):

```powershell
.\install.ps1 -Router 192.168.1.1
```

Default result: SOCKS5 on `:10808` (UDP on), HTTP on `:10809`, no authentication (limit it to LAN if the router is exposed).

## Commands

```
pattx update               update to the latest release (does nothing if already latest)
pattx update v26.10.9      install a specific release
pattx rollback             go back to the previous core
pattx status               version, service, ports, PassWall2 path
pattx passwall on|off      use this core in PassWall2 / back to stock xray
pattx ech                  make ECH DNS servers of PassWall2 nodes go direct (also automatic)
pattx auto on|off          daily auto-update (cron, 04:17)
pattx uninstall
```

## Use it as a standalone local proxy

Put your own Xray JSON config in `/opt/pattx/config.json` (outbounds, routing, ...), then:

```sh
/opt/pattx/xray run -test -c /opt/pattx/config.json && /etc/init.d/pattx restart
```

## Use it inside PassWall2

```sh
pattx passwall on     # sets passwall2 global_app xray_file to /opt/pattx/xray
```

**Compatibility shim (only for PassWall2 older than 26.10):** newer Xray cores (including this one) removed the outbound field `proxySettings`
(now `streamSettings.sockopt.dialerProxy`), while PassWall2 26.8.x still writes it, so the core refuses to start
("Core NOT RUNNING"). `pattx passwall on` adds a tiny shim to `/usr/lib/lua/luci/passwall2/util_xray.lua`
that converts the field; `pattx passwall off` / `uninstall` restore the original (backup: `util_xray.lua.pattx.bak`).
A PassWall2 upgrade overwrites the file, so run `pattx passwall on` (or `pattx update`) again afterwards.
PassWall2 26.10.1 and newer already use `dialerProxy`, there the shim is skipped automatically (tested with 26.10.1).

PassWall2 generates its own config, so a field that only exists in patterniha's core must be accepted by PassWall2's node editor to be used.
Do not press PassWall2's own "update Xray" button, it would replace the core. Use `pattx update`.

## ECH nodes (automatic)

Nodes with ECH (`echConfigList: cloudflare-ech.com+udp://8.8.8.8`) make the core resolve an ECH record from that DNS server.
On the router that query leaves from the router itself and PassWall2's transparent proxy sends it into the same node,
which needs ECH to connect: a loop (`Failed to query ECH DNS record ... i/o timeout` in the PassWall2 xray log).

`pattx` fixes this automatically: `pattx ech` reads the ECH DNS server of every PassWall2 node and adds it to PassWall2's
direct IP list (`/usr/share/passwall2/direct_ip`), then restarts PassWall2 if something changed. It runs by itself
- when you save/apply PassWall2 settings in LuCI (procd `config.change` trigger, so new or imported ECH nodes are covered),
- when the `pattx` service starts (boot) and on `pattx install` / `pattx update` / `pattx passwall on`.

Note: a PassWall2 package upgrade overwrites `direct_ip`; run `pattx ech` (or `pattx update`) afterwards.
Hostnames in `ech_config` (e.g. `https://dns.google/dns-query`) are resolved at sync time and their IPv4 addresses are added.

## Troubleshooting: router cannot resolve DNS through a Cloudflare-fronted node

If a node sits behind Cloudflare (Workers/CDN), TCP DNS to Cloudflare IPs such as `1.1.1.1:53` through it can fail
(`failed to read response length ... closed pipe`) and the router then loses DNS while PassWall2 is on, so even `pattx update` cannot
reach GitHub. Use DoH for the remote DNS: PassWall2 > Basic Settings > DNS > Remote DNS protocol `DoH`,
e.g. `https://dns.google/dns-query,8.8.8.8`. If you are stuck, `/etc/init.d/passwall2 stop`, run `pattx update`, then start PassWall2 again.

## Limits

- Only the Xray core. patterniha's `sing-box` / `mihomo` builds are not used (glibc / x86-64-v3 requirements).
- Tested: x86_64 OpenWrt 25.12 only. Other architectures are mapped in the script but untested.
- Updating needs access to github.com from the router.

## License and credits

Scripts in this repository: MIT. The Xray core is by patterniha and [XTLS/Xray-core](https://github.com/XTLS/Xray-core) (MPL-2.0) and is
downloaded from its own releases, not redistributed here.
