#!/usr/bin/env bash
# colorburst — bật mạng cho máy ảo / enable networking for the VM
#
# Chạy MỘT LẦN với sudo. Sau đó ./start-vm.sh vẫn chạy bằng tài khoản thường
# và máy ảo có mạng.
#   Run this ONCE with sudo. After that ./start-vm.sh still runs as your
#   normal user, and the VM has internet.
#
# Vì sao cần sudo: máy ảo cần một card mạng ảo trên máy thật, và chỉ root mới
# tạo được. Việc tạo là một lần; chạy máy ảo thì không cần quyền root.
#   Why sudo is needed: the VM needs a virtual network device on the host, and
#   only root can create one. That is a one-time step; running the VM is not
#   privileged.
#
# ĐÚNG NĂM VIỆC NÀY, không gì khác / EXACTLY THESE FIVE THINGS, nothing else:
#
#   1. tạo thiết bị mạng ảo (TAP) tên colorburst0, thuộc sở hữu của bạn
#      create a TAP device named colorburst0, owned by you
#   2. gán địa chỉ 192.168.77.1/24 cho nó
#      give it the address 192.168.77.1/24
#   3. bật chuyển tiếp IPv4 (net.ipv4.ip_forward=1)
#      turn on IPv4 forwarding
#   4. thêm MỘT luật NAT để máy ảo ra được internet qua card mạng thật
#      add ONE NAT rule so the VM can reach the internet through your real NIC
#   5. chạy dnsmasq trên colorburst0 để cấp địa chỉ cho máy ảo
#      run dnsmasq on colorburst0 to hand the VM an address
#
# Gỡ bỏ tất cả / undo everything:
#
#     sudo ./setup-network.sh --remove
#
# Các thay đổi trên KHÔNG tự động khôi phục sau khi khởi động lại máy; chạy lại
# script này sau mỗi lần khởi động, hoặc gỡ bỏ khi không dùng nữa.
#   None of this survives a reboot; run the script again after booting, or
#   remove it when you are done.
set -eu

TAP=colorburst0
SUBNET=192.168.77
HOST_IP="${SUBNET}.1"
DHCP_FROM="${SUBNET}.10"
DHCP_TO="${SUBNET}.100"
GUEST_MAC="52:54:00:c0:1b:57"
GUEST_IP="${SUBNET}.2"
PIDFILE=/run/colorburst-dnsmasq.pid

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

die() { printf '\n'; red "$1"; shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done; printf '\n'; exit 1; }

# `run` prints every privileged command before running it, so nothing this
# script does to your system is invisible.
run() { printf '    $ %s\n' "$*"; "$@"; }

[ "$(id -u)" -eq 0 ] || die \
    "Cần chạy với sudo / This needs sudo." \
    "" \
    "    sudo ./setup-network.sh"

# The user who will own the TAP: the one who invoked sudo, not root.
OWNER="${SUDO_USER:-}"
[ -n "$OWNER" ] || die \
    "Không xác định được người dùng / Cannot tell which user to give the device to." \
    "" \
    "Hãy chạy qua sudo từ tài khoản thường / Run it through sudo from your normal account:" \
    "    sudo ./setup-network.sh"

# --- teardown -------------------------------------------------------------

if [ "${1:-}" = "--remove" ]; then
    step "Đang gỡ bỏ / Removing colorburst networking…"

    if [ -f "$PIDFILE" ]; then
        run kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi

    WAN="$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}' || true)"
    if [ -n "$WAN" ]; then
        while iptables -t nat -C POSTROUTING -s "${SUBNET}.0/24" -o "$WAN" -j MASQUERADE 2>/dev/null; do
            run iptables -t nat -D POSTROUTING -s "${SUBNET}.0/24" -o "$WAN" -j MASQUERADE
        done
        while iptables -C FORWARD -i "$TAP" -o "$WAN" -j ACCEPT 2>/dev/null; do
            run iptables -D FORWARD -i "$TAP" -o "$WAN" -j ACCEPT
        done
        while iptables -C FORWARD -i "$WAN" -o "$TAP" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; do
            run iptables -D FORWARD -i "$WAN" -o "$TAP" -m state --state RELATED,ESTABLISHED -j ACCEPT
        done
    fi

    if ip link show "$TAP" >/dev/null 2>&1; then
        run ip link del "$TAP"
    fi

    printf '\n  Đã gỡ xong / Removed. IPv4 forwarding was left as it was.\n\n'
    exit 0
fi

# --- checks ---------------------------------------------------------------

for tool in ip iptables dnsmasq; do
    command -v "$tool" >/dev/null 2>&1 || die \
        "Thiếu '$tool' / Missing '$tool'." \
        "" \
        "Cài đặt / Install it:" \
        "    Debian/Ubuntu:  sudo apt install iproute2 iptables dnsmasq-base" \
        "    Fedora:         sudo dnf install iproute iptables dnsmasq" \
        "    Arch:           sudo pacman -S iproute2 iptables dnsmasq"
done

WAN="$(ip route show default | awk '/default/{print $5; exit}')"
[ -n "$WAN" ] || die \
    "Máy thật đang không có kết nối mạng / This machine has no default route." \
    "" \
    "Hãy kết nối mạng rồi chạy lại / Connect to a network and try again."

step "colorburst network setup"
info "Card mạng thật / your network interface : $WAN"
info "Thiết bị ảo sẽ tạo / device to create    : $TAP  ($HOST_IP)"
info "Chủ sở hữu / owned by                    : $OWNER"
info "Máy ảo sẽ nhận địa chỉ / VM will get     : $GUEST_IP"

# --- 1. the TAP device ----------------------------------------------------

step "1/5  Thiết bị mạng ảo / virtual network device"
if ip link show "$TAP" >/dev/null 2>&1; then
    info "$TAP đã tồn tại, bỏ qua / already exists, skipping"
else
    run ip tuntap add mode tap user "$OWNER" vnet_hdr "$TAP"
fi

# --- 2. address -----------------------------------------------------------

step "2/5  Địa chỉ / address"
if ip -4 addr show dev "$TAP" | grep -q "$HOST_IP"; then
    info "đã có / already set"
else
    run ip addr add "${HOST_IP}/24" dev "$TAP"
fi
run ip link set "$TAP" up

# --- 3. forwarding --------------------------------------------------------

step "3/5  Chuyển tiếp IPv4 / IPv4 forwarding"
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    info "đã bật / already on"
else
    info "Bật chuyển tiếp cho phép máy ảo đi ra internet qua máy thật."
    info "This lets traffic from the VM pass through to the internet."
    run sysctl -q -w net.ipv4.ip_forward=1
fi

# --- 4. NAT ---------------------------------------------------------------

step "4/5  NAT"
if iptables -t nat -C POSTROUTING -s "${SUBNET}.0/24" -o "$WAN" -j MASQUERADE 2>/dev/null; then
    info "luật đã có / rule already present"
else
    run iptables -t nat -A POSTROUTING -s "${SUBNET}.0/24" -o "$WAN" -j MASQUERADE
fi
iptables -C FORWARD -i "$TAP" -o "$WAN" -j ACCEPT 2>/dev/null ||
    run iptables -A FORWARD -i "$TAP" -o "$WAN" -j ACCEPT
iptables -C FORWARD -i "$WAN" -o "$TAP" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null ||
    run iptables -A FORWARD -i "$WAN" -o "$TAP" -m state --state RELATED,ESTABLISHED -j ACCEPT

# --- 5. DHCP --------------------------------------------------------------

step "5/5  Cấp địa chỉ cho máy ảo / address server for the VM"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    info "dnsmasq đang chạy / already running"
else
    rm -f "$PIDFILE"
    # --bind-interfaces plus --interface keeps this dnsmasq strictly on the
    # colorburst device; it will not answer on your real network.
    run dnsmasq \
        --interface="$TAP" \
        --bind-interfaces \
        --except-interface=lo \
        --dhcp-range="${DHCP_FROM},${DHCP_TO},12h" \
        --dhcp-host="${GUEST_MAC},${GUEST_IP}" \
        --pid-file="$PIDFILE"
fi

cat <<EOF

  ---------------------------------------------------------------
  Xong / Done.

  Giờ chạy máy ảo như bình thường (KHÔNG cần sudo):
  Now start the VM as usual (NO sudo):

      ./start-vm.sh colorburst.bin

  Gỡ bỏ mọi thay đổi ở trên / undo everything above:

      sudo ./setup-network.sh --remove

  Lưu ý: các thiết lập này mất sau khi khởi động lại máy thật.
  Note: none of this survives a reboot of your computer.
  ---------------------------------------------------------------

EOF
