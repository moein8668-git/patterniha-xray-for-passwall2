#!/bin/sh
# pattx - install / update patterniha's custom Xray core on OpenWrt (any architecture).
#
# SPECIAL THANKS to patterniha, the creator of this core (PattN / PattNG / patterniha/xray-core).
# All credit for the core goes to him: https://github.com/patterniha
# This script only downloads his official release and wires it into OpenWrt. It is fully vibe-coded.
#
#   sh pattx.sh install        install (or update) core + service, and put this script at /usr/bin/pattx
#   pattx update               update to the latest release (no-op if already latest)
#   pattx update v26.10.9      install a specific release
#   pattx rollback             go back to the previous core
#   pattx status               version, service state, ports
#   pattx passwall on|off      use this core inside PassWall2 / go back to the stock xray
#   pattx auto on|off          daily auto-update via cron
#   pattx uninstall

REPO="patterniha/xray-core"
DIR="/opt/pattx"
SVC="/etc/init.d/pattx"
SELF="/usr/bin/pattx"
CRON="/etc/crontabs/root"

say() { printf '[pattx] %s\n' "$*"; }
die() { printf '[pattx] ERROR: %s\n' "$*" >&2; exit 1; }

fetch() { # fetch URL OUTFILE
	if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -m 600 -o "$2" "$1"
	else wget -q -O "$2" "$1"; fi
}

detect_asset() {
	m=$(uname -m)
	[ -f /etc/openwrt_release ] && . /etc/openwrt_release
	case "$m" in
	x86_64) echo linux-64 ;;
	i386|i486|i586|i686) echo linux-32 ;;
	aarch64*|arm64) echo linux-arm64-v8a ;;
	armv7*|armv8l) echo linux-arm32-v7a ;;
	armv6*) echo linux-arm32-v6 ;;
	arm*) echo linux-arm32-v5 ;;
	riscv64) echo linux-riscv64 ;;
	loongarch64) echo linux-loong64 ;;
	ppc64le) echo linux-ppc64le ;;
	mips64)
		case "$DISTRIB_ARCH" in *el*) echo linux-mips64le ;; *) echo linux-mips64 ;; esac ;;
	mips*)
		# OpenWrt arch names: mips_* = big endian, mipsel_* = little endian
		case "$DISTRIB_ARCH" in mipsel*) echo linux-mips32le ;; mips64el*) echo linux-mips64le ;; *) echo linux-mips32 ;; esac ;;
	*) die "unsupported architecture: $m" ;;
	esac
}

latest_tag() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSI -m 20 "https://github.com/$REPO/releases/latest" | tr -d '\r' | sed -n 's/^[Ll]ocation:.*\/tag\///p' | tail -n1
	else
		wget -q -S --spider --max-redirect=0 "https://github.com/$REPO/releases/latest" 2>&1 | tr -d '\r' | sed -n 's/.*[Ll]ocation:.*\/tag\///p' | tail -n1
	fi
}

cur_version() { [ -x "$DIR/xray" ] && "$DIR/xray" version 2>/dev/null | head -n1 | awk '{print $2}'; }

need_unzip() {
	command -v unzip >/dev/null 2>&1 && return 0
	say "unzip not found, installing it..."
	if command -v apk >/dev/null 2>&1; then apk add unzip >/dev/null 2>&1
	elif command -v opkg >/dev/null 2>&1; then opkg update >/dev/null 2>&1; opkg install unzip >/dev/null 2>&1; fi
	command -v unzip >/dev/null 2>&1 || die "unzip is required (apk add unzip / opkg install unzip)"
}

write_service() {
	cat > "$SVC" <<'EOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10
start_service() {
	procd_open_instance
	procd_set_param command /opt/pattx/xray run -c /opt/pattx/config.json
	procd_set_param env XRAY_LOCATION_ASSET=/opt/pattx
	procd_set_param respawn
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_close_instance
}
service_triggers() { procd_add_reload_trigger pattx; }
EOF
	chmod +x "$SVC"
}

write_default_config() {
	[ -f "$DIR/config.json" ] && return 0
	cat > "$DIR/config.json" <<'EOF'
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {"tag":"socks-in","listen":"0.0.0.0","port":10808,"protocol":"socks","settings":{"udp":true,"auth":"noauth"}},
    {"tag":"http-in","listen":"0.0.0.0","port":10809,"protocol":"http"}
  ],
  "outbounds": [ {"tag":"direct","protocol":"freedom"} ]
}
EOF
}

migrate_old() { # from the early "pattn" naming
	[ -d /opt/pattn ] || return 0
	[ -f "$DIR/config.json" ] || cp -f /opt/pattn/config.json "$DIR/config.json" 2>/dev/null
	[ -f /etc/init.d/pattn ] && { /etc/init.d/pattn stop; /etc/init.d/pattn disable; rm -f /etc/init.d/pattn; } >/dev/null 2>&1
	rm -rf /opt/pattn /usr/bin/pattn; sed -i '/pattn update/d' "$CRON" 2>/dev/null
	if [ "$(uci -q get passwall2.@global_app[0].xray_file)" = /opt/pattn/xray ]; then
		uci set passwall2.@global_app[0].xray_file="$DIR/xray"; uci commit passwall2
	fi
	say "migrated from old pattn install"
}

do_install() { # $1 = tag or empty (latest)
	tag="$1"
	[ -n "$tag" ] || tag=$(latest_tag)
	[ -n "$tag" ] || die "cannot find the latest release (no internet / GitHub blocked?)"
	cur=$(cur_version)
	if [ "$FORCE" != 1 ] && [ -n "$cur" ] && [ "v$cur" = "$tag" ]; then
		say "already on $tag"; return 0
	fi
	asset=$(detect_asset)
	url="https://github.com/$REPO/releases/download/$tag/Xray-$asset.zip"
	need_unzip
	tmp=/tmp/pattx.$$; rm -rf "$tmp"; mkdir -p "$tmp"
	say "downloading $tag ($asset)..."
	fetch "$url" "$tmp/x.zip" || die "download failed: $url"
	if fetch "$url.dgst" "$tmp/x.dgst" 2>/dev/null; then
		want=$(sed -n 's/^SHA2-256= *//p' "$tmp/x.dgst" | tr -d '\r ')
		got=$(sha256sum "$tmp/x.zip" | awk '{print $1}')
		[ -z "$want" ] || [ "$want" = "$got" ] || die "checksum mismatch (want $want got $got)"
		say "checksum OK"
	else
		say "warning: no .dgst available, checksum skipped"
	fi
	unzip -oq "$tmp/x.zip" -d "$tmp/out" || die "unzip failed"
	[ -f "$tmp/out/xray" ] || die "xray binary not found in archive"
	chmod +x "$tmp/out/xray"
	"$tmp/out/xray" version >/dev/null 2>&1 || die "new core does not run on this device"

	mkdir -p "$DIR"
	migrate_old
	write_default_config
	if [ -x "$DIR/xray" ]; then [ -f "$SVC" ] && "$SVC" stop >/dev/null 2>&1; cp -f "$DIR/xray" "$DIR/xray.prev"; fi
	cp -f "$tmp/out/xray" "$DIR/xray.new" && mv -f "$DIR/xray.new" "$DIR/xray"
	for f in geoip.dat geosite.dat; do [ -f "$tmp/out/$f" ] && cp -f "$tmp/out/$f" "$DIR/$f"; done
	rm -rf "$tmp"

	"$DIR/xray" run -test -c "$DIR/config.json" >/dev/null 2>&1 || say "warning: config.json does not pass 'xray run -test'"
	write_service
	"$SVC" enable
	"$SVC" restart
	# PassWall2 uses this core? restart it so it picks up the new binary
	if [ "$(uci -q get passwall2.@global[0].enabled)" = 1 ] && [ "$(uci -q get passwall2.@global_app[0].xray_file)" = "$DIR/xray" ]; then
		/etc/init.d/passwall2 restart >/dev/null 2>&1
	fi
	say "installed: $("$DIR/xray" version | head -n1)"
}

install_self() {
	src="$0"
	[ "$(readlink -f "$src" 2>/dev/null)" = "$SELF" ] && return 0
	[ -f "$src" ] && cp -f "$src" "$SELF" && chmod +x "$SELF"
}

cmd="${1:-help}"
case "$cmd" in
install)
	mkdir -p "$DIR"; install_self
	do_install "$2"
	say "SOCKS5 :10808  HTTP :10809  config: $DIR/config.json  (manage with: pattx help)"
	;;
update)
	[ -x "$DIR/xray" ] || die "not installed, run: sh pattx.sh install"
	do_install "$2"
	;;
force-update) FORCE=1 do_install "$2" ;;
rollback)
	[ -x "$DIR/xray.prev" ] || die "no previous core"
	"$SVC" stop; mv -f "$DIR/xray" "$DIR/xray.bad"; mv -f "$DIR/xray.prev" "$DIR/xray"; "$SVC" start
	say "rolled back to $(cur_version)"
	;;
status)
	say "installed: $(cur_version) | latest: $(latest_tag)"
	"$SVC" running >/dev/null 2>&1 && say "service: running" || say "service: stopped"
	netstat -lnt 2>/dev/null | grep -E ':(10808|10809) ' | awk '{print "  listening " $4}'
	say "passwall2 xray path: $(uci -q get passwall2.@global_app[0].xray_file)"
	;;
passwall)
	command -v uci >/dev/null && uci -q get passwall2.@global_app[0] >/dev/null || die "PassWall2 not installed"
	case "$2" in
	on) uci set passwall2.@global_app[0].xray_file="$DIR/xray" ;;
	off) uci set passwall2.@global_app[0].xray_file=/usr/bin/xray ;;
	*) die "usage: pattx passwall on|off" ;;
	esac
	uci commit passwall2
	[ "$(uci -q get passwall2.@global[0].enabled)" = 1 ] && /etc/init.d/passwall2 restart >/dev/null 2>&1
	say "PassWall2 xray = $(uci get passwall2.@global_app[0].xray_file)"
	;;
auto)
	sed -i '/pattx update/d' "$CRON" 2>/dev/null
	case "$2" in
	on) echo "17 4 * * * $SELF update >/tmp/pattx-update.log 2>&1" >> "$CRON"; say "daily auto-update on" ;;
	off) say "auto-update off" ;;
	*) die "usage: pattx auto on|off" ;;
	esac
	/etc/init.d/cron restart >/dev/null 2>&1
	;;
uninstall)
	"$SVC" stop 2>/dev/null; "$SVC" disable 2>/dev/null
	rm -f "$SVC"; sed -i '/pattx update/d' "$CRON" 2>/dev/null
	uci -q get passwall2.@global_app[0] >/dev/null && uci set passwall2.@global_app[0].xray_file=/usr/bin/xray && uci commit passwall2
	rm -rf "$DIR" "$SELF"
	say "removed"
	;;
*)
	sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
	;;
esac
