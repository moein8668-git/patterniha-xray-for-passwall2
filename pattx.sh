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
#   pattx ech                  make DNS servers of ECH nodes (PassWall2) go direct (automatic, see README)
#   pattx dns [udp [IP]|restore]  PassWall2 Remote DNS: warn about tcp, switch to UDP (asks first, auto rollback)
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

# procd prints a harmless "Command failed: Not found" when it deletes a service it doesn't know yet (fresh install)
svc_restart() { "$SVC" restart 2>&1 | grep -v 'Not found'; return 0; }

write_service() { # sets SVC_CHANGED=1 if the init script content changed
	SVC_CHANGED=0
	cat > "$SVC.new" <<'EOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10
service_triggers() {
	procd_add_reload_trigger pattx
	# new/changed PassWall2 nodes (e.g. ECH) -> make their DNS go direct
	procd_add_config_trigger config.change passwall2 /usr/bin/pattx ech
}
start_service() {
	[ -x /usr/bin/pattx ] && /usr/bin/pattx ech >/dev/null 2>&1
	procd_open_instance
	procd_set_param command /opt/pattx/xray run -c /opt/pattx/config.json
	procd_set_param env XRAY_LOCATION_ASSET=/opt/pattx
	procd_set_param respawn
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_close_instance
}
EOF
	if [ -f "$SVC" ] && cmp -s "$SVC" "$SVC.new"; then rm -f "$SVC.new"
	else mv -f "$SVC.new" "$SVC"; SVC_CHANGED=1; fi
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

PW_LUA="/usr/lib/lua/luci/passwall2/util_xray.lua"
PW_MARK="-- pattx-compat"

# Newer Xray cores removed outbound "proxySettings" (now streamSettings.sockopt.dialerProxy).
# PassWall2 (as of 26.8.x) still writes the old field, so the core refuses the config.
# This adds a tiny shim to PassWall2 that converts it when the config is written. Idempotent.
patch_passwall() {
	[ -f "$PW_LUA" ] || return 0
	grep -q -e "$PW_MARK" "$PW_LUA" && return 0
	# newer PassWall2 already uses dialerProxy: nothing to do
	grep -q 'proxySettings' "$PW_LUA" || { rm -f "$PW_LUA.pattx.bak"; return 0; }
	cp -f "$PW_LUA" "$PW_LUA.pattx.bak"   # always from the current (unpatched) file
	cat > /tmp/pattx-shim.lua <<'EOF'
do -- pattx-compat
	local _s = jsonc.stringify
	jsonc.stringify = function(cfg, ...)
		if type(cfg) == "table" and type(cfg.outbounds) == "table" then
			for _, o in ipairs(cfg.outbounds) do
				local ps = o.proxySettings
				if ps ~= nil then
					o.proxySettings = nil
					if o.protocol ~= "dns" and ps.tag then
						o.streamSettings = o.streamSettings or {}
						o.streamSettings.sockopt = o.streamSettings.sockopt or {}
						o.streamSettings.sockopt.dialerProxy = ps.tag
					end
				end
			end
		end
		return _s(cfg, ...)
	end
end
EOF
	awk -v f=/tmp/pattx-shim.lua '{print} /^local jsonc = api.jsonc/ && !d {while((getline l < f)>0) print l; d=1}' "$PW_LUA.pattx.bak" > "$PW_LUA.new" \
		&& mv -f "$PW_LUA.new" "$PW_LUA" && rm -f /tmp/pattx-shim.lua
	grep -q -e "$PW_MARK" "$PW_LUA" && say "PassWall2 compat shim applied (proxySettings -> dialerProxy)" || say "warning: shim not applied"
}

unpatch_passwall() {
	[ -f "$PW_LUA.pattx.bak" ] && mv -f "$PW_LUA.pattx.bak" "$PW_LUA" && say "PassWall2 compat shim removed"
}

# ECH nodes ("echConfigList": "cloudflare-ech.com+udp://8.8.8.8") make the core query that DNS server itself.
# On the router that query would go into PassWall2's transparent proxy -> same node -> loop (timeout).
# ech_sync finds every ECH DNS server used by PassWall2 nodes and adds it to PassWall2's direct IP list.
PW_DIRECT="/usr/share/passwall2/direct_ip"

ech_sync() {
	[ -f "$PW_DIRECT" ] || return 0
	command -v uci >/dev/null 2>&1 || return 0
	changed=0
	for v in $(uci -q show passwall2 | sed -n "s/^passwall2\.[^.]*\.ech_config='\(.*\)'$/\1/p"); do
		case "$v" in *://*) ;; *) continue ;; esac
		srv="${v#*://}"; srv="${srv%%/*}"; srv="${srv%%:*}"; srv="${srv%%\?*}"
		[ -n "$srv" ] || continue
		case "$srv" in
		*[!0-9.]*) ips=$(nslookup "$srv" 2>/dev/null | awk '/^Name:/{f=1} f && /^Address/{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') ;;
		*) ips="$srv" ;;
		esac
		for ip in $ips; do
			grep -qx -e "$ip" "$PW_DIRECT" && continue
			[ -n "$(tail -c1 "$PW_DIRECT")" ] && echo >> "$PW_DIRECT"
			echo "$ip" >> "$PW_DIRECT"
			say "ECH DNS $ip -> PassWall2 direct list"
			changed=1
		done
	done
	if [ "$changed" = 1 ] && [ "$(uci -q get passwall2.@global[0].enabled)" = 1 ]; then
		/etc/init.d/passwall2 restart >/dev/null 2>&1 &
	fi
	return 0
}

# --- Remote DNS of PassWall2 -------------------------------------------------------------
# Many CDN-fronted nodes (e.g. behind Cloudflare) close TCP/53 but pass UDP/53 and HTTPS, so PassWall2's
# default "tcp://1.1.1.1" Remote DNS makes every domain fail to resolve in transparent mode, while the node
# "test" button still passes (it lets the node resolve the name). This switches Remote DNS to UDP, with a
# warning, a confirmation, an automatic check and an automatic rollback.
PW_CFG="passwall2.@global[0]"

dns_cur() { echo "$(uci -q get $PW_CFG.remote_dns_protocol)://$(uci -q get $PW_CFG.remote_dns) (detour: $(uci -q get $PW_CFG.remote_dns_detour))"; }

ask_yes() { # ask_yes "question" ; default No ; non-interactive = No
	[ -t 0 ] || return 1
	printf '[pattx] %s [y/N] ' "$1"; read -r a
	case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

dns_apply_check() { # restart PassWall2 and verify that domains resolve
	[ "$(uci -q get passwall2.@global[0].enabled)" = 1 ] || { say "PassWall2 is off, not verified"; return 0; }
	/etc/init.d/passwall2 restart >/dev/null 2>&1
	say "checking that domains resolve (about 20 s)..."
	sleep 20
	nslookup github.com 127.0.0.1 2>/dev/null | grep -q 'Address: [0-9]'
}

dns_restore() {
	[ -f "$DIR/dns.prev" ] || die "nothing to restore"
	. "$DIR/dns.prev"
	uci set $PW_CFG.remote_dns_protocol="$P"; uci set $PW_CFG.remote_dns="$S"
	if [ -n "$D" ]; then uci set $PW_CFG.remote_dns_doh="$D"; else uci -q delete $PW_CFG.remote_dns_doh; fi
	uci commit passwall2
	[ "$(uci -q get passwall2.@global[0].enabled)" = 1 ] && /etc/init.d/passwall2 restart >/dev/null 2>&1
	rm -f "$DIR/dns.prev"
	say "Remote DNS restored: $(dns_cur)"
}

dns_udp() { # dns_udp [IP] [-y]
	ip=""; yes=0
	for a in "$@"; do case "$a" in -y|--yes) yes=1 ;; *) ip="$a" ;; esac; done
	command -v uci >/dev/null && uci -q get passwall2.@global[0] >/dev/null || die "PassWall2 not installed"
	if [ -z "$ip" ]; then
		ip=$(uci -q get $PW_CFG.remote_dns)
		case "$ip" in ""|*[!0-9.]*) ip=8.8.8.8 ;; esac
	fi
	case "$ip" in *[!0-9.]*|"") die "usage: pattx dns udp [DNS_IPV4] [-y]" ;; esac
	say "current Remote DNS: $(dns_cur)"
	say "WARNING: UDP DNS will be sent to $ip through your proxy node, in plain text inside the tunnel."
	say "  - the node/server must allow UDP/53 (not all do). pattx checks it and rolls back if names do not resolve."
	say "  - DoH is the safer choice if your node cannot do UDP: set it in LuCI > PassWall2 > DNS."
	say "  - it changes your PassWall2 DNS settings (a backup is kept: 'pattx dns restore' undoes it)."
	if [ "$yes" != 1 ]; then ask_yes "Switch Remote DNS to udp://$ip ?" || { say "not changed"; return 0; }; fi
	P=$(uci -q get $PW_CFG.remote_dns_protocol); S=$(uci -q get $PW_CFG.remote_dns); D=$(uci -q get $PW_CFG.remote_dns_doh)
	printf "P='%s'\nS='%s'\nD='%s'\n" "$P" "$S" "$D" > "$DIR/dns.prev"
	uci set $PW_CFG.remote_dns_protocol=udp; uci set $PW_CFG.remote_dns="$ip"; uci commit passwall2
	if dns_apply_check; then say "OK: Remote DNS is now udp://$ip and names resolve"
	else say "names do NOT resolve with UDP on this node, rolling back"; dns_restore; fi
}

dns_hint() { # called after 'passwall on': warn about tcp Remote DNS
	[ "$(uci -q get $PW_CFG.remote_dns_protocol)" = tcp ] || return 0
	say "NOTE: PassWall2 Remote DNS is tcp://$(uci -q get $PW_CFG.remote_dns). Many CDN-fronted nodes (Cloudflare) block TCP/53,"
	say "      then nothing resolves in transparent mode although the node test passes. Fix: 'pattx dns udp' (or use DoH)."
	if ask_yes "Switch Remote DNS to UDP now?"; then dns_udp -y; fi
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
		say "already on $tag"
		write_service; "$SVC" enable
		[ "$SVC_CHANGED" = 1 ] && { say "service script updated"; svc_restart; }
		[ "$(uci -q get passwall2.@global_app[0].xray_file)" = "$DIR/xray" ] && { patch_passwall; ech_sync; }
		return 0
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
	svc_restart
	# PassWall2 uses this core? restart it so it picks up the new binary
	if [ "$(uci -q get passwall2.@global_app[0].xray_file)" = "$DIR/xray" ]; then
		patch_passwall   # re-apply after a PassWall2 upgrade
		ech_sync
		[ "$(uci -q get passwall2.@global[0].enabled)" = 1 ] && /etc/init.d/passwall2 restart >/dev/null 2>&1
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
	# local fixes first, they must work even if DNS/internet is broken (e.g. ECH loop)
	if [ -x "$DIR/xray" ]; then write_service; [ "$SVC_CHANGED" = 1 ] && svc_restart; ech_sync; fi
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
ech) ech_sync ;;
dns)
	case "$2" in
	udp) shift 2; dns_udp "$@" ;;
	restore) dns_restore ;;
	""|show) say "PassWall2 Remote DNS: $(dns_cur)"; dns_hint ;;
	*) die "usage: pattx dns [show|udp [IP] [-y]|restore]" ;;
	esac
	;;
passwall)
	command -v uci >/dev/null && uci -q get passwall2.@global_app[0] >/dev/null || die "PassWall2 not installed"
	case "$2" in
	on) uci set passwall2.@global_app[0].xray_file="$DIR/xray"; patch_passwall ;;
	off) uci set passwall2.@global_app[0].xray_file=/usr/bin/xray; unpatch_passwall ;;
	*) die "usage: pattx passwall on|off" ;;
	esac
	uci commit passwall2
	[ "$2" = on ] && ech_sync
	[ "$(uci -q get passwall2.@global[0].enabled)" = 1 ] && /etc/init.d/passwall2 restart >/dev/null 2>&1
	say "PassWall2 xray = $(uci get passwall2.@global_app[0].xray_file)"
	[ "$2" = on ] && dns_hint
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
	unpatch_passwall
	rm -f "$SVC"; sed -i '/pattx update/d' "$CRON" 2>/dev/null
	uci -q get passwall2.@global_app[0] >/dev/null && uci set passwall2.@global_app[0].xray_file=/usr/bin/xray && uci commit passwall2
	rm -rf "$DIR" "$SELF"
	say "removed"
	;;
*)
	sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
	;;
esac
