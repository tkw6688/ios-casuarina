# tiffany: first diagnostic image (D0)

This directory is the Xiaomi Mi 5X (`tiffany`, MSM8953) port of the vince loader.
It is **not** a ROM and it never writes to the phone: everything is started with
`fastboot boot`.

## What D0 is

`tiffany/out/tiffany-d0.img` (built by `tiffany/tools/build_d0.sh`) contains:

- the tiffany loader (`tiffany/shim`, panel 1080×1920, 24 bpp, stride 3240);
- the fake XNU payload (`tiffany/prebuilt/fakexnu.macho`);
- the tiffany Apple Device Tree (`tiffany/tools/mkadt_tiffany.py`);
- the tiffany DTB (`tiffany/prebuilt/tiffany.dtb`, board-id `0x1000b`, msm-id `0x125`).

It checks the loader contract without starting XNU.

## Build locally

```bash
export PATH=/mnt/data/tiffany-refs/toolchain/usr/lib/llvm-19/bin:/mnt/data/tiffany-refs/toolchain/usr/bin:$PATH
cd /mnt/data/tiffany-work
bash tiffany/tools/build_d0.sh --rebuild-dtb
```

Output: `tiffany/out/tiffany-d0.img`.

## On the phone

1. Back up `persist`, `modemst1`, `modemst2`, `fsg`, `fsc`, `boot`, `recovery` first.
2. Put the phone in fastboot (Power + Volume Down).
3. `fastboot boot tiffany-d0.img`.

Expected screen (from top):

```
TIFFANY M3b: XNU loader
fb 00000000 00000000 00000000 00000000
img=0x10080000 dtb=0x13400000 EL=1 MPIDR=0x000000
ramdisk 0x13600000 - 0x13607720 (... KiB)
phys 0x20000000 size 0x60000000
virt ...
entry va ...
...
FAKE XNU reached (loader test)
LOADER TEST PASSED        <- green
```

The exact addresses may differ: record them. The `fb` line is the first four 32-bit
words LK left at `0x90001000` before the loader cleared the screen; non-zero values
confirm the base address, and their layout hints at 24 vs 32 bpp. If the screen is
black or the text is skewed/wrong colors, the LK framebuffer is not 24 bpp/stride
3240; report a photo and we will try stride 3264 or 32 bpp/4320.

## D1: the real kernel

After D0 passes:

1. Run the `xnu` workflow on the `tiffany` branch (it sets `TOPAZ_4K=1`, `VINCE=1`,
   `TIFFANY=1`) and download the `xnu-kernel` artifact; the file is
   `kernel.development.sweet`.
2. Put the real iPhone X device tree at `research/ipsw-x/d22ap.adt` (extracted from
   the 16.7.16 iPhone10,3 IPSW; see `tools/mkadt.py`). Without it the kernel still
   boots, but MobileGestalt sees no `/product`.
3. Pack and boot:

   ```bash
   python3 tiffany/tools/tiffany_pack.py kernel.development.sweet out/tiffany-d1.img \
     --cmdline "debug=0xc serial=3 cpus=8 keepsyms=1 wdt=-1"
   fastboot boot tiffany-d1.img
   ```

D1 has no iOS root yet: it is expected to print the XNU early console and stop at
`Waiting on Apple_HFS` (or panic looking for a root device). The screen surviving
that far means the panel and the tiffany kernel constants are right.

## Safety

- Never `fastboot flash` this image.
- If `fastboot boot` is rejected, stop; do not fall back to flashing `boot`.
- Nothing in D0 writes to eMMC.
