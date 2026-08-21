#!/usr/bin/env bash
#
#  colorburst — start-vm.sh
#
#  Chạy colorburst trong một cửa sổ trên máy của bạn / Run colorburst in a
#  window on your own machine, with real GPU acceleration.
#
#  Usage:
#      ./start-vm.sh                       # find the image automatically
#      ./start-vm.sh path/to/image.bin     # or point at it yourself
#
#  Everything it needs is in the "runtime/" folder next to this script.
#  Nothing is installed on your system and the downloaded image is never
#  modified.
#
#  Knobs (environment variables, all optional):
#      CB_WINDOW=1600x900   window size in desktop points (default 1600x900)
#      CB_HIDPI=1           set to 1 on a HiDPI/200% desktop for a sharper,
#                           same-sized window (renders at 2x internally)
#      CB_MEM=6144          guest RAM in MB          (default 6144)
#      CB_CPUS=4            guest CPU cores          (default 4)
#      CB_STATE=~/.local/share/colorburst   where the writable disk lives
#      CB_FRESH=1           throw away the saved state and start clean
#
set -uo pipefail

# ---------------------------------------------------------------- pretty ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    B=$'\033[1m'; R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; N=$'\033[0m'
else
    B=""; R=""; G=""; Y=""; N=""
fi
say()  { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$G$B" "$N" "$*"; }
warn() { printf '%s warning:%s %s\n' "$Y$B" "$N" "$*" >&2; }

# die "one-line problem" "what to do about it" ["more"...]
die() {
    printf '\n%sKhông chạy được / Cannot start:%s %s\n\n' "$R$B" "$N" "$1" >&2
    shift
    for line in "$@"; do printf '  %s\n' "$line" >&2; done
    printf '\n' >&2
    exit 1
}

trap 'die "an unexpected internal error occurred (line $LINENO)" \
     "This is a bug in start-vm.sh. Please report it, and include the last" \
     "20 lines printed above."' ERR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------- the parts ----
RUNTIME="${CB_RUNTIME:-$HERE/runtime}"
CROSVM="$RUNTIME/bin/crosvm"
LIBS="$RUNTIME/lib"

[ -x "$CROSVM" ] || die \
    "the colorburst runtime is missing (expected $CROSVM)" \
    "You probably downloaded start-vm.sh on its own. Download the full" \
    "release archive (colorburst-vm-<version>-x86_64.tar.gz), unpack it," \
    "and run ./start-vm.sh from inside the unpacked folder."

# ----------------------------------------------------------- 1. the CPU -----
step "Kiểm tra máy / Checking your computer"

case "$(uname -m)" in
    x86_64|amd64) ;;
    *) die "colorburst needs a 64-bit Intel or AMD computer (yours is $(uname -m))" \
           "Apple Silicon and ARM machines are not supported yet." ;;
esac

if ! grep -qE '^flags.*\b(vmx|svm)\b' /proc/cpuinfo 2>/dev/null; then
    die "your CPU does not report hardware virtualisation support" \
        "colorburst runs as a virtual machine, which needs that feature." \
        "It is often switched off in the BIOS/UEFI setup screen — look for" \
        "a setting called \"Intel VT-x\", \"AMD-V\", \"SVM\" or just" \
        "\"Virtualization\" and turn it on." \
        "If you are already inside a virtual machine, this will not work."
fi

# ------------------------------------------------------- 2. /dev/kvm --------
if [ ! -e /dev/kvm ]; then
    die "/dev/kvm does not exist on this system" \
        "That is the Linux kernel's virtualisation device. Usually it means" \
        "virtualisation is disabled in the BIOS/UEFI (see \"Intel VT-x\" /" \
        "\"AMD-V\" / \"SVM\"), or the kvm module is not loaded:" \
        "" \
        "    sudo modprobe kvm_amd     # AMD CPUs" \
        "    sudo modprobe kvm_intel   # Intel CPUs"
fi
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    die "you do not have permission to use /dev/kvm" \
        "Add yourself to the 'kvm' group, then log out and back in:" \
        "" \
        "    sudo usermod -aG kvm $USER" \
        "" \
        "(Logging out matters — group changes only apply to new sessions.)" \
        "Check it worked with: ls -l /dev/kvm  and  id"
fi

# -------------------------------------------------------- 3. the screen -----
# crosvm draws into a Wayland window. On an X11-only desktop there is no
# Wayland socket to draw into, and we say so instead of failing obscurely.
WAYLAND_SOCK=""
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    cand="$XDG_RUNTIME_DIR/${WAYLAND_DISPLAY:-wayland-0}"
    [ -S "$cand" ] && WAYLAND_SOCK="$cand"
    if [ -z "$WAYLAND_SOCK" ] && [ -n "${WAYLAND_DISPLAY:-}" ] \
       && [ -S "${WAYLAND_DISPLAY}" ]; then
        WAYLAND_SOCK="$WAYLAND_DISPLAY"      # absolute path form
    fi
fi
if [ -z "$WAYLAND_SOCK" ]; then
    if [ -n "${DISPLAY:-}" ]; then
        die "your desktop is running on X11, and colorburst needs Wayland" \
            "The accelerated window is drawn through Wayland; the X11 path" \
            "cannot show it." \
            "" \
            "On the login screen, click the gear/settings icon and pick the" \
            "\"Wayland\" session (GNOME and KDE both offer one), log in, and" \
            "run ./start-vm.sh again." \
            "" \
            "If you cannot switch, see RUNNING-VM.md for the Docker fallback."
    fi
    die "no graphical desktop found" \
        "colorburst opens a window, so it has to be started from inside a" \
        "graphical session — not over a plain SSH connection and not from a" \
        "text console." \
        "" \
        "(Looked for \$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY and found nothing.)"
fi

# ------------------------------------------------------ 4. the host GPU -----
if [ ! -e /dev/dri/renderD128 ]; then
    warn "no GPU render node (/dev/dri/renderD128) — graphics will be slow."
    warn "If you have a discrete GPU, install its Mesa/OpenGL drivers."
fi

# --------------------------------------------------------- 5. the image -----
step "Tìm ảnh hệ điều hành / Locating the colorburst image"

IMAGE="${1:-${CB_IMAGE:-}}"
if [ -z "$IMAGE" ]; then
    for c in "$HERE"/*.bin \
             "$HERE"/image/*.bin \
             "$HOME/Downloads"/colorburst*.bin \
             "$HOME/Downloads"/chromiumos_test_image.bin; do
        [ -f "$c" ] && { IMAGE="$c"; break; }
    done
fi
[ -n "$IMAGE" ] || die \
    "could not find a colorburst disk image (.bin)" \
    "Download the image, then either put it next to this script or tell" \
    "this script where it is:" \
    "" \
    "    ./start-vm.sh /path/to/colorburst.bin"
[ -f "$IMAGE" ] || die "that image file does not exist: $IMAGE" \
    "Check the path and try again."
IMAGE="$(readlink -f "$IMAGE")"
[ -r "$IMAGE" ] || die "cannot read the image file: $IMAGE" \
    "Fix its permissions, e.g.:  chmod +r \"$IMAGE\""

# The kernel is booted directly (colorburst images ship it beside the .bin).
KERNEL="${CB_KERNEL:-}"
if [ -z "$KERNEL" ]; then
    for c in "$(dirname "$IMAGE")/boot_images/vmlinuz" \
             "$(dirname "$IMAGE")/vmlinuz" \
             "$HERE/vmlinuz"; do
        [ -f "$c" ] && { KERNEL="$c"; break; }
    done
fi
[ -n "$KERNEL" ] && [ -f "$KERNEL" ] || die \
    "found the disk image but not its kernel (vmlinuz)" \
    "colorburst boots the kernel directly, so the file 'vmlinuz' must sit" \
    "next to the image (or in a 'boot_images' folder beside it)." \
    "Image: $IMAGE" \
    "If you unpacked a release archive, unpack all of it, not just the .bin."

say "    image:  $IMAGE"
say "    kernel: $KERNEL"

# -------------------------------------------- 6. memory, disk, workspace ----
STATE="${CB_STATE:-${XDG_DATA_HOME:-$HOME/.local/share}/colorburst}"
mkdir -p "$STATE" || die "cannot create $STATE" "Check permissions on your home folder."
DISK="$STATE/disk.qcow2"
LOG="$STATE/console.log"

[ "${CB_FRESH:-0}" = 1 ] && { step "Xoá trạng thái cũ / Discarding saved state"; rm -f "$DISK"; }

# RAM: ChromeOS wants ~6 GB. With much less, the browser is killed in a loop.
TOTAL_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
MEM="${CB_MEM:-6144}"
if [ "$TOTAL_MB" -lt 8000 ]; then
    if [ "$TOTAL_MB" -lt 5000 ]; then
        die "this computer has only ${TOTAL_MB} MB of RAM" \
            "colorburst needs about 8 GB of RAM in the machine to run" \
            "comfortably (it gives ${MEM} MB to the virtual machine and" \
            "your own desktop needs the rest)." \
            "You can try anyway with:  CB_MEM=3072 ./start-vm.sh"
    fi
    MEM=3072
    warn "only ${TOTAL_MB} MB RAM detected — giving the VM ${MEM} MB."
    warn "colorburst may be slow or unstable. 8 GB or more is recommended."
fi

# Disk: the writable overlay grows as you use colorburst.
FREE_MB=$(df -Pm "$STATE" | awk 'NR==2{print $4}')
if [ "${FREE_MB:-0}" -lt 4096 ]; then
    die "only ${FREE_MB} MB of free disk space in $STATE" \
        "colorburst needs a few GB of room for its writable disk." \
        "Free up some space, or put the state somewhere roomier:" \
        "" \
        "    CB_STATE=/some/big/disk/colorburst ./start-vm.sh"
fi

CPUS="${CB_CPUS:-4}"
HOSTCPUS=$(nproc 2>/dev/null || echo 4)
[ "$CPUS" -gt "$HOSTCPUS" ] && CPUS="$HOSTCPUS"

# ------------------------------------------------------- 7. window size -----
# CB_WINDOW is the size of the window you see, in desktop points.
# On a HiDPI desktop (200% scaling) CB_HIDPI=1 renders 2 guest pixels per
# point, so the window stays the same size but everything is crisp.
WINDOW="${CB_WINDOW:-1600x900}"
case "$WINDOW" in
    [0-9]*x[0-9]*) ;;
    *) die "CB_WINDOW must look like 1600x900, got '$WINDOW'" \
           "Example:  CB_WINDOW=1280x720 ./start-vm.sh" ;;
esac
SCALE=1
[ "${CB_HIDPI:-0}" = 1 ] && SCALE=2
W=$(( ${WINDOW%%x*} * SCALE ))
H=$(( ${WINDOW##*x} * SCALE ))

# ----------------------------------------------- 8. the writable overlay ----
# A copy-on-write file that keeps every change; the .bin is opened read-only
# as its backing file and never written to.
export LD_LIBRARY_PATH="$LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ ! -s "$DISK" ]; then
    step "Chuẩn bị đĩa / Preparing a writable disk (the download is not modified)"
    rm -f "$DISK"
    if ! "$CROSVM" create_qcow2 --backing-file "$IMAGE" "$DISK" >/dev/null 2>&1; then
        rm -f "$DISK"
        die "could not create the writable disk in $STATE" \
            "Check that $STATE is writable and that the image file is a" \
            "colorburst disk image:" \
            "    $IMAGE"
    fi
fi

# ---------------------------------------------------------- 8b. network -----
# Networking is opt-in and configured separately by setup-network.sh, which is
# the only part that needs root. If the device it creates is present we attach
# it; otherwise the VM runs without a NIC.
#
# Nothing here needs privileges: setup-network.sh created the TAP with
# `user <you>`, so opening it is an ordinary file operation.
NET_ARGS=()
if ip link show colorburst0 >/dev/null 2>&1; then
    NET_ARGS=(--net "tap-name=colorburst0,mac=52:54:00:c0:1b:57")
    NET_LINE="Mạng / network    colorburst0 (có kết nối / connected)"
else
    NET_LINE="Mạng / network    không có — chạy 'sudo ./setup-network.sh' để bật
                    none — run 'sudo ./setup-network.sh' to enable"
fi

# --------------------------------------------------------------- 9. go ------
cat <<EOF

  ${B}colorburst${N}
  ---------------------------------------------------------------
  Cửa sổ / window   ${WINDOW} points$( [ "$SCALE" = 2 ] && echo "  (HiDPI, ${W}x${H} pixels)" )
  RAM               ${MEM} MB
  CPU               ${CPUS} cores
  Đĩa / disk        ${DISK}
  Nhật ký / log     ${LOG}

  A window will open in a few seconds and colorburst will start up.
  The first boot takes about a minute; later ones are quicker.

  Để dừng / to stop: close the window, or press Ctrl-C here.
  Your changes are kept in the disk file above. To start over from a
  clean system:   CB_FRESH=1 ./start-vm.sh

  ${NET_LINE}
  ---------------------------------------------------------------

EOF

step "Khởi động / Starting colorburst…"

# DISPLAY must be unset: with it set, crosvm picks its X11 display backend,
# which cannot present the accelerated (virgl) framebuffer — you get a black
# window. CROSVM_DISPLAY_SCALE is our patched knob for guest-pixels-per-point.
#
# The root filesystem is mounted "ro", as on a real ChromeOS device. It is
# ext2, so it has no journal: mounted "rw", closing the window mid-write leaves
# it damaged, and the *next* boot then loops restarting the browser and never
# reaches a screen. Everything the system writes lives on the stateful
# partition, which is a separate, journalled filesystem and stays writable.
#
# The disk is attached over virtio-SCSI (/dev/sda), not virtio-blk (/dev/vda):
# the colorburst kernel builds virtio_blk as a MODULE, so a --block root disk
# never appears and the guest hangs forever at "Waiting for root device
# /dev/vda3". (This script shipped with --block from the amd64-generic days,
# where virtio_blk was built in; it could not boot a colorburst image at all.)
trap - ERR          # from here on, a non-zero exit is handled, not trapped
env -u DISPLAY CROSVM_DISPLAY_SCALE="$SCALE" \
"$CROSVM" run \
    --disable-sandbox \
    --wayland-sock "$WAYLAND_SOCK" \
    --display-window-keyboard --display-window-mouse \
    --mem "$MEM" --cpus "$CPUS" \
    --gpu "backend=virglrenderer,context-types=virgl2,egl=true,displays=[[mode=windowed[$W,$H]]]" \
    ${NET_ARGS[@]+"${NET_ARGS[@]}"} \
    --scsi-block "path=$DISK,ro=false" \
    --serial "type=file,path=$LOG,hardware=serial,console=true,num=1,earlycon=true" \
    -p "root=/dev/sda3 ro rootwait noinitrd cros_debug cros_efi loglevel=7 console=ttyS0 earlyprintk=serial,ttyS0,115200 vt.global_cursor_default=0" \
    "$KERNEL" 2> >(grep --line-buffered -vF 'failed to get wl_buffer for dmabuf' >&2)
rc=$?

# 0 = the window was closed / the guest powered off.
# 130 = Ctrl-C, 143 = terminated by something else. All are normal stops.
case "$rc" in 0|130|143) rc=0 ;; esac

if [ "$rc" -ne 0 ]; then
    printf '\n'
    die "colorburst stopped unexpectedly (exit code $rc)" \
        "The boot messages from inside the virtual machine are in:" \
        "    $LOG" \
        "" \
        "Common causes:" \
        "  * another copy of colorburst is already running" \
        "  * the disk image is damaged or was only partly downloaded" \
        "  * not enough free memory (close some applications)" \
        "" \
        "Starting fresh often fixes a damaged saved state:" \
        "    CB_FRESH=1 ./start-vm.sh"
fi

step "colorburst đã dừng / colorburst has stopped. Hẹn gặp lại!"
