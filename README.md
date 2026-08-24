# colorburst

*[Tiếng Việt](README-vi.md)*

colorburst is a free operating system for ordinary PCs. You can install, use,
copy and modify it, at no cost.

It is built from the source of **ChromiumOS** — the open-source code Google
publishes, which is also the basis of the ChromeOS that runs on Chromebooks.
colorburst is not ChromeOS and is not affiliated with Google.

> **This is experimental.** The project is early. Expect rough edges, and parts
> of the interface that still call themselves "Chrome" or "Chromium" — the
> rebranding is incomplete, not deliberate.

## What it does differently

- **The account lives on the machine.** You create it on first boot. No Google
  account, and no network needed to sign in.
- **No Google services.** Nothing is sent anywhere to log in or to use the
  machine.
- **It updates itself** from colorburst's own update server.

## Who it is for

People who mainly use a web browser. There is nothing to learn and nothing to
configure. It runs on a desktop or laptop made in roughly the **last ten
years**.

## Try it from a USB stick

This runs on real hardware without touching the internal disk.

1. Download `colorburst-<version>.zip` from
   [Releases](https://github.com/colorburst-os/colorburst/releases). You need a
   USB stick of **16 GB or more**.
2. Write the image to the stick.

   **Windows / macOS:** [balenaEtcher](https://etcher.balena.io/) accepts the
   `.zip` directly.

   **Linux:**

   ```bash
   unzip colorburst-<version>.zip
   sudo dd if=colorburst-<version>.bin of=/dev/sdX bs=4M status=progress conv=fsync
   ```

   Replace `/dev/sdX` with your stick. **Writing to the wrong disk erases it.**
   Check with `lsblk` first.
3. Boot from the stick — usually F12, F2 or Esc at power-on. You may need to
   turn off **Secure Boot** in BIOS/UEFI.

> The current release starts in Vietnamese. The first screen has a language
> selector; pick English there. Separate per-language images are coming.

## Install it

Boot from the stick, then choose the install option on the welcome screen.

**Installing erases the entire target disk.** Back up first.

## Your account

On the welcome screen, choose **"Create a local account"**, give it a name and
a password.

That account exists only on your machine. If you forget the password there is
no recovery — nothing is stored on a server that could reset it for you.

## Build it yourself

Everything builds in Docker; nothing is installed on your host. The toolchain
and full instructions are in
[chromiumos-devenv](https://github.com/colorburst-os/chromiumos-devenv).

Budget ~200 GB of disk and several hours for the first build.

## Known limitations

- No password recovery.
- DRM content (Netflix and similar) does not play.
- Branding is incomplete: the boot screen and some dialogs still say Chromium.

## Origin and licence

colorburst is a fork of ChromiumOS. The original code belongs to the ChromiumOS
authors under the BSD 3-clause licence; other components keep their own.

Not affiliated with Google. "Chrome", "ChromeOS" and "Chromebook" are Google
trademarks.

## About the name

On analogue colour television (NTSC, PAL), every scan line opens with a short
burst of signal — a few cycles of the colour subcarrier, about 3.58 MHz on
NTSC. It carries no picture. Its only job is to give the receiver's oscillator
a phase reference. Without it the picture still appears, but the colours are
wrong.

A small repeated reference, so that everything else comes out right.
