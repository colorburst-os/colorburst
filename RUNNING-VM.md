# Running colorburst in a VM: how `start-vm.sh` works and how the runtime is built

Maintainer document (English). The user-facing README is Vietnamese and only
links here.

`start-vm.sh` boots a colorburst disk image on the user's own Linux machine, in
a GPU-accelerated window, with **no installation** and **no root**. It does that
by shipping our own build of **crosvm** (ChromeOS's hypervisor) plus exactly two
private libraries, and borrowing everything else from the host.

---

## 1. Recommendation, and why

**Ship a plain tarball: prebuilt `crosvm` + two bundled `.so` files + this
launcher. Not AppImage, not Docker.**

The decisive fact, discovered by actually measuring it, is that crosvm's
external surface is tiny. `ldd` of our `crosvm` on a machine that has never had
any ChromeOS tooling on it resolves *everything* from the host except one
library:

| Needed by crosvm | Where it comes from |
|---|---|
| `libc`, `libm`, `libgcc_s`, `libcap` | host (universal) |
| `libwayland-client`, `libX11`, `libXext`, `libxcb`, `libffi`, `libexpat`, `libXau`, `libXdmcp` | host (any graphical desktop has these) |
| `libdrm` | host |
| **`libvirglrenderer.so.1`** | **bundled** — not installed by default on any desktop distro |
| **`libgbm.so.1` (minigbm)** | **bundled** — must be the ChromeOS fork, see below |

That is a **12 MB** payload. There is no Rust runtime to ship, no Mesa, no
GL stack. A tarball is therefore the whole job:

```
colorburst-vm-<version>-x86_64/
├── start-vm.sh
├── runtime/
│   ├── bin/crosvm                    # 11 MB
│   └── lib/
│       ├── libvirglrenderer.so.1     # 650 KB
│       └── libgbm.so.1               # 625 KB (minigbm)
├── colorburst.bin                    # the disk image (~11 GB, shipped separately)
└── vmlinuz                           # the guest kernel
```

(`runtime/` is a build artifact — produced by `tools/build-runtime.sh` and
attached to a release, not something to keep in git.)

**Why not AppImage.** AppImage buys three things: single-file distribution, a
mount-based FS, and a `LD_LIBRARY_PATH`-style bootstrap. We do not benefit from
any of them.

- We are already shipping an 11 GB `.bin` next to the launcher, so "one file"
  was never on the table; the user unpacks an archive either way.
- AppImage needs FUSE (`libfuse2` is *not* installed on Ubuntu 24.04+ by
  default, which produces exactly the kind of cryptic failure this script
  exists to avoid), or `--appimage-extract-and-run`, which is just a tarball
  with extra steps.
- The classic AppImage GL hazard is real and it is the same hazard either way:
  you must **not** bundle Mesa/EGL/GL/`libdrm`, because the host's GL driver
  stack must match the host kernel's DRM driver. AppImage tooling
  (`linuxdeploy`, `appimagetool`) *wants* to hoover up transitive dependencies
  and would happily pull in `libEGL`, `libGLdispatch`, `libdrm` and friends via
  `libvirglrenderer`'s dependency graph. Fighting the tool's excludelist is more
  work than copying two files.

So AppImage adds a runtime dependency (FUSE) and a footgun (over-bundling GL) in
exchange for packaging convenience we do not need. A tarball is more
predictable, trivially inspectable, and trivially reproducible in CI.

**Why not Docker as the primary path.** It works — it is what
`chromium-os/run-crosvm.sh` does today — but for an end user it means:
install Docker, add yourself to the `docker` group, log out and back in, pull or
build a 2.4 GB image, and grant the container `/dev/kvm`, `/dev/dri`, the
Wayland socket and `--ipc=host`. That is a bigger ask than the thing it is
delivering, and every one of those steps is a place a non-expert gets stuck.
It stays as a **fallback** for hosts where the tarball's assumptions break
(non-glibc distros, very old distros — see Limitations).

**Verdict:** tarball primary, Docker documented as fallback, AppImage not worth
building.

---

## 2. What is bundled, and what is deliberately not

### Bundled

**`libvirglrenderer.so.1`** — the host-side half of the virgl protocol: it takes
the GL command stream the guest emits and replays it on the host GPU. Distros
mostly ship it only as a QEMU dependency and a desktop user will not have it.
It is safe to bundle because it is a *translator*, not a driver: it talks to the
GPU through the host's own `libEGL`/`libGL`, which it dlopens through
`libepoxy` at runtime.

**`libgbm.so.1` — but ours is minigbm**, the ChromeOS fork of libgbm. This one
is not optional: crosvm's `wl-dmabuf`/gbm code calls symbols Mesa's libgbm does
not export (`gbm_bo_get_map_info`, `minigbm_create_default_device`), so linking
against the host's `libgbm.so.1` fails at load time. minigbm's `SONAME` *is*
`libgbm.so.1`, so once it is on the library path it satisfies everyone in the
process — including virglrenderer's own `libgbm.so.1` dependency. That is
exactly what happens inside the dev container today, and it is a proven-good
configuration, not an accident we are tolerating.

### Deliberately **not** bundled

`libEGL`, `libGL`, `libGLdispatch`, `libgbm` (Mesa's), `libdrm`,
`libvulkan`, `/usr/lib/.../dri/*_dri.so`, `libva`, `libepoxy`.

These *must* come from the host. The host's Mesa driver is matched to the host's
kernel DRM driver (the same amdgpu/i915/nouveau kernel module version); a
bundled Mesa talking to a different kernel driver either refuses to load the
DRI driver and silently falls back to `llvmpipe` — i.e. software rendering, the
exact failure we are packaging to avoid — or crashes. Bundling `libdrm` has the
same problem one layer down. `libepoxy` is the GL entry-point loader; if we
bundled it, it would still `dlopen` the host `libGL`, so bundling it buys
nothing and risks an ABI mismatch.

Rule of thumb for anyone changing the bundle: **anything that talks to
`/dev/dri` on behalf of the host GPU belongs to the host.** Only the two
ChromeOS-specific pieces are ours.

---

## 3. Building the runtime (CI recipe)

The build happens in the `cros-crosvm` container from the dev repo
(`chromium-os/docker/crosvm/Dockerfile`, Ubuntu 26.04). Full detail lives in
`chromium-os/CROSVM.md`; this is the packaging-relevant subset.

```bash
# 0. In the chromium-os checkout. minijail is an empty stub in the repo
#    checkout; point it at the tree copy.
ln -sf ../../minijail chromiumos/src/platform/crosvm/third_party/minijail

# 1. minigbm (produces the libgbm.so.1 we ship)
env CROS_IMAGE=cros-crosvm ./cros-sdk.sh bash -c '
  cd src/platform/minigbm &&
  make install DESTDIR=$HOME/chromiumos/.cache/minigbm LIBDIR=/lib'

# 2. crosvm, linked against that minigbm
env CROS_IMAGE=cros-crosvm NET=host ./cros-sdk.sh bash -c '
  export CPATH=$HOME/chromiumos/.cache/minigbm/usr/include \
         PKG_CONFIG_PATH=$HOME/chromiumos/.cache/minigbm/lib/pkgconfig \
         RUSTFLAGS="-Lnative=$HOME/chromiumos/.cache/minigbm/lib"
  cd src/platform/crosvm &&
  cargo build --profile chromeos --features "virgl_renderer,wl-dmabuf,x" \
        --target-dir $HOME/chromiumos/.cache/crosvm-target'
```

Note: drop the `-Clink-arg=-Wl,-rpath,...` that `CROSVM.md` uses for local
development. A baked-in `RUNPATH` pointing at a build-machine path is harmless
(it just fails to resolve on the user's machine) but it is noise in a shipped
binary; the launcher sets `LD_LIBRARY_PATH` instead.

Then assemble — this part is scripted as **`tools/build-runtime.sh`** (run it
from this repo, with the `chromium-os` checkout as a sibling directory):

```bash
./tools/build-runtime.sh [path-to-chromium-os]
```

It copies the three files into `runtime/`, then runs two checks that between
them catch the whole class of packaging bugs:

1. `LD_LIBRARY_PATH=runtime/lib ldd runtime/bin/crosvm` has no `not found`.
2. `libEGL` / `libGL` / `libdrm` / `libvulkan` / `libepoxy` resolve to **host**
   paths, never into `runtime/lib`. If one ever resolves inside the bundle, we
   have shipped a Mesa stack and the user gets `llvmpipe`.

Both are CI-ready as-is (non-zero exit on failure). The release tarball is then
just `tar czf colorburst-vm-<version>-x86_64.tar.gz start-vm.sh runtime/`.

The image and kernel are produced by the normal ChromeOS build
(`cros build-image --board=amd64-generic test`) and shipped separately;
`vmlinuz` comes from `images/amd64-generic/latest/boot_images/`.

---

## 4. What `start-vm.sh` does

Roughly in order, and every failure is a plain-language message with a fix, not
a stack trace (`set -e` plus an `ERR` trap, so an unexpected error still prints
something actionable):

1. **CPU** — x86-64, and `vmx`/`svm` in `/proc/cpuinfo`. If missing, it says to
   turn on "Intel VT-x / AMD-V / SVM" in the BIOS.
2. **`/dev/kvm`** — exists, readable and writable. If not readable it prints
   `sudo usermod -aG kvm $USER` **and** the fact that you must log out and back
   in, which is the step people miss.
3. **Display** — finds `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`. If the session is
   X11 it says so explicitly and tells the user to pick the Wayland session at
   the login screen; if there is no session at all (SSH, text console) it says
   that instead. This matters because crosvm's Wayland display backend is only
   used when `--wayland-sock` is passed, and its X11 backend **cannot present a
   3D virgl scanout** — you would get a black window (`CROSVM.md`).
4. **GPU render node** — warns (does not fail) if `/dev/dri/renderD128` is
   absent.
5. **Image** — argument, `$CB_IMAGE`, or a search of the script's own folder and
   `~/Downloads`. Finds `vmlinuz` beside it (or in `boot_images/`).
6. **Copy-on-write overlay** — `crosvm create_qcow2 --backing-file <image>` into
   `~/.local/share/colorburst/disk.qcow2`. **The downloaded 11 GB `.bin` is
   opened read-only as a backing file and never written to**; all guest writes
   land in the overlay, which starts at 320 KB. `CB_FRESH=1` deletes the overlay
   to get a pristine system back, which is also the standard "it broke" fix.
7. **Resources** — 6144 MB / 4 vCPUs by default, dropped to 3072 MB with a
   warning on machines under 8 GB, refused under 5 GB. ChromeOS with too little
   RAM does not fail loudly; it OOM-kills Chrome in a silent loop, so guessing
   low is worse than refusing.
8. **Runs crosvm**, unsetting `DISPLAY` (see 3) and filtering one stderr line
   (below).

### The window-size knob

`CB_WINDOW` is the size of the window **in desktop points**, default
`1600x900` — chosen to fit a 1366x768-and-up laptop screen. `CB_HIDPI=1`
doubles the guest framebuffer to 2 guest pixels per point, so on a 4K/200%
desktop the window is the same physical size but pixel-perfect and crisp.

Internally this is the dev repo's `CROS_DISPLAY` / `CROS_SCALE` pair
(`CROS_DISPLAY = CB_WINDOW × SCALE`, `CROSVM_DISPLAY_SCALE = SCALE`), reframed
so the user sets the thing they actually care about — how big the window is —
instead of a framebuffer size that has to be divided by a scale factor. The dev
default of `3840x2160@scale2` is right for a 4K/200% desktop and produces an
unusable, screen-overflowing window on anything else, which is why the
user-facing default is not that.

`CROSVM_DISPLAY_SCALE` is our patch; upstream crosvm hardcodes scale 2 (a
ChromeOS/exo assumption). The same patch series fixes window decorations and
pointer coordinate scaling — without it the window has no title bar and clicks
land in the wrong place.

---

## 5. Verified on

A machine with **no** ChromeOS tooling installed outside Docker: no crosvm, no
virglrenderer, no minigbm.

- Host: Ubuntu 26.04, glibc 2.43, KDE Plasma on Wayland, AMD Radeon
  (radeonsi, `renderD128`), 30 GB RAM.
- Result: the bundled crosvm boots the colorburst image outside any container
  and opens a decorated window showing the Vietnamese OOBE screen, keyboard and
  mouse working.
- Host-side GL is genuinely live — crosvm's own log reports
  `gl_version 32 - es profile enabled` / `GLSL feature level 430` from
  virglrenderer, which only happens when the host GL context came up.
- **Guest-side renderer string, read from inside the running guest:**

  ```
  OpenGL renderer string: virgl (AMD Ryzen 7 9700X 8-Core Processor (radeonsi, raphae...
  ```

  virgl on radeonsi — the host GPU — not `llvmpipe`. Acceleration is real.

Getting that string without a network in the guest is a useful trick worth
recording: boot with `--keyboard /tmp/kbd.sock` (crosvm *connects* to a unix
**stream** socket you listen on, and each event is a packed
`<HHI` = type/code/value `virtio_input_event`), inject Ctrl+Alt+F2 to reach
VT2, log in as `root` / `test0000`, and exfiltrate through the kernel log,
which is already on the serial port:

```
wflinfo -p null -a gles2 2>/dev/null | grep -i renderer > /dev/kmsg
```

`> /dev/ttyS0` does *not* work (SELinux), `> /dev/kmsg` does. The image has no
getty on the serial port, so the console is output-only without this.

### One harmless error to know about

The console prints `ERROR gpu_display_wl: failed to get wl_buffer for dmabuf`,
often thousands of times. It comes from the **virtio-wayland** path
(`dwl_context_dmabuf_new` in `gpu_display/display_wl.c`), which exists so guest
*Wayland clients* can share buffers with the host compositor — a Crostini
feature ChromeOS itself does not use here. The scanout path is unaffected and
the display works. `start-vm.sh` filters that one line out of stderr so users
do not see a wall of red; everything else is passed through.

---

## 6. Known limitations

- **No network inside the VM.** crosvm has no user-mode networking on Linux
  (no slirp in this build): a network device means a TAP interface, and creating
  one needs `CAP_NET_ADMIN`, i.e. root. Requiring `sudo` in a
  "double-click and it runs" script is the wrong trade, so the default is a
  VM with no NIC. Consequences: OOBE cannot do its network check or sign-in,
  and there is no NTP. This is the biggest gap and the thing to fix next.
  Two routes, in preference order:
  1. **`passt` in vhost-user mode** — fully unprivileged user-mode networking,
     packaged in Debian/Ubuntu, and crosvm can attach to it with
     `--vhost-user type=net,socket=…`. Not tested yet; it would need `passt`
     either installed by the user or bundled (it is a small static-ish binary
     with no GPU entanglement, so bundling is safe).
  2. **Opt-in `--network` flag** that runs a documented `sudo ip tuntap add …`
     + `dnsmasq` sequence, i.e. what `chromium-os/run-crosvm.sh` does inside
     its container. Works, but asks for root.
- **Wayland only.** X11 sessions are rejected up front rather than shown a
  black window. crosvm's X11 backend cannot present virgl scanouts.
- **x86-64 only**, and the guest kernel is booted directly (`root=/dev/vda3`,
  no bootloader, which also bypasses dm-verity — required for a modified image).
- **glibc**, and reasonably current. The binaries are built on Ubuntu 26.04, so
  they need glibc ≥ 2.43-ish; older LTS distros and musl (Alpine) will not load
  them. Building the runtime on the oldest distro we want to support is the
  standard fix; until then those users get the Docker fallback.
- **Closing the window shuts the VM down**, and anything that reboots the guest
  (including finishing OOBE) exits crosvm — the guest reboot is not caught and
  restarted. Re-run `./start-vm.sh`; state is preserved in the overlay.
- The overlay grows monotonically; `CB_FRESH=1` is the only reclaim.
- One VM at a time per state directory. Two concurrent runs would fight over
  the same `disk.qcow2`; use `CB_STATE=…` to separate them.

## 7. Verifying acceleration

If graphics ever look wrong, the single question that matters is whether the
*guest* is using virgl or falling back to software. From inside the guest:

```
wflinfo -p null -a gles2 | grep -i renderer
OpenGL renderer string: virgl (AMD Ryzen ... (radeonsi))
```

`llvmpipe` there means the **image** lacks Mesa's virgl driver
(`VIDEO_CARDS` must contain `virgl`) and no amount of host-side configuration
will help — see `chromium-os/GRAPHICS.md`. Getting a shell in the guest means
either the dev repo's networked container path (`chromium-os/run-crosvm.sh`,
then `ssh -p 9222 root@localhost`) or a VT2 login in the window
(`Ctrl+Alt+F2`, user `root`, password `test0000` on test images) — see
section 5 for the scripted version of the latter.

A cheaper host-side smoke test, when you only want to know whether the host
half came up: `./start-vm.sh` prints crosvm's own log, and

```
INFO rutabaga_gfx::virgl_renderer] gl_version 32 - es profile enabled
INFO rutabaga_gfx::virgl_renderer] GLSL feature level 430
```

means virglrenderer got a real GL context from the host driver.

## 8. Docker fallback

If the tarball will not run — old distro, musl, no Wayland — the dev
environment's containerised path still works and is documented in
`chromium-os/README.md`:

```bash
git clone <chromium-os repo> && cd chromium-os
docker build -t cros-crosvm docker/crosvm
./run-crosvm.sh /path/to/colorburst.bin
```

It additionally gives you networking and SSH into the guest, at the price of
Docker plus a privileged container.

## Networking

Opt-in, and split so that **only the setup step is privileged**:

- `sudo ./setup-network.sh` — once per boot of the host. Creates a TAP device
  `colorburst0` owned by the invoking user, gives it `192.168.77.1/24`, turns on
  IPv4 forwarding, adds one MASQUERADE rule plus two FORWARD rules, and starts a
  `dnsmasq` bound strictly to that interface (`--bind-interfaces
  --interface=colorburst0`) handing the guest `192.168.77.2`.
- `./start-vm.sh` — unprivileged, as always. It attaches `--net
  tap-name=colorburst0` **only if the device exists**; otherwise the VM runs
  with no NIC and the banner says so. Opening a TAP created with `user <you>`
  is an ordinary file operation, so no privilege is needed at run time.
- `sudo ./setup-network.sh --remove` — deletes the rules, the device, and stops
  the dnsmasq it started. IPv4 forwarding is left as found, since something else
  on the machine may want it.

The script echoes every privileged command as it runs it (`run()` prints `$ …`),
so nothing it does to the host is invisible. It is idempotent: each step checks
whether it is already done.

Nothing survives a host reboot. That is deliberate — a persistent systemd unit
would be a larger commitment to make on someone's machine than a script they
re-run.

`passt`/`pasta` in vhost-user mode would remove the sudo step entirely and is
worth revisiting, but it is unverified against our crosvm build, whereas the TAP
path is the same one the development environment has used all along.

**UNVERIFIED**: the setup script has not been executed end to end here, because
this environment has no passwordless sudo. Its syntax, its refusal-without-root
path, and `start-vm.sh`'s detection of an absent device are all checked; the
privileged steps are the same `ip`/`iptables`/`dnsmasq` sequence that
`run-crosvm.sh` performs inside the container, where it is known to work.
