#!/bin/bash
# Build the tiffany D0 diagnostic image: tiffany DTB + loader shim + ADT + fakexnu payload.
#
#   bash tiffany/tools/build_d0.sh [--rebuild-dtb]
#
# Needs: clang, ld.lld, llvm-objcopy, llvm-readelf, dtc, python3.
# The default toolchain is the locally extracted Debian lld-19/llvm-19/dtc in
# /mnt/data/tiffany-refs/toolchain; override with TOOLCHAIN=...
# The DTB is compiled from the MSM8953 kernel tree; override with KERNEL_TREE=...
# Nothing here touches a phone.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
KERNEL_TREE=${KERNEL_TREE:-/mnt/data/tiffany-refs/kernel-msm8953}
TOOLCHAIN=${TOOLCHAIN:-/mnt/data/tiffany-refs/toolchain}
OUT=${OUT:-$ROOT/tiffany/out}
Q=$KERNEL_TREE/arch/arm64/boot/dts/qcom
DTS=$Q/msm8953-qrd-sku3-tiffany.dts
DTB=$ROOT/tiffany/prebuilt/tiffany.dtb
LOADER=$ROOT/tiffany/prebuilt/loader.Image
FAKE=$ROOT/tiffany/prebuilt/fakexnu.macho

export PATH="$TOOLCHAIN/usr/lib/llvm-19/bin:$TOOLCHAIN/usr/bin:$PATH"

command -v clang >/dev/null || { echo "clang missing" >&2; exit 1; }
command -v ld.lld >/dev/null || { echo "ld.lld missing (set TOOLCHAIN)" >&2; exit 1; }
command -v dtc >/dev/null || { echo "dtc missing (set TOOLCHAIN)" >&2; exit 1; }
[ -f "$DTS" ] || { echo "missing $DTS (set KERNEL_TREE)" >&2; exit 1; }
[ -f "$FAKE" ] || { echo "missing $FAKE" >&2; exit 1; }

mkdir -p "$OUT" "$(dirname "$DTB")"

if [ "${1:-}" = "--rebuild-dtb" ] || [ ! -f "$DTB" ]; then
	echo "=== DTB: $DTS"
	clang -E -P -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
		-I"$Q" -I"$KERNEL_TREE/arch/arm64/boot/dts" -I"$KERNEL_TREE/include" \
		"$DTS" -o "$OUT/tiffany.dts.pre"
	dtc -q -I dts -O dtb -i "$Q" -o "$DTB" "$OUT/tiffany.dts.pre"
	echo "=== DTB: $DTB ($(stat -c %s "$DTB") bytes)"
else
	echo "=== DTB: reusing $DTB"
fi

echo "=== loader"
( cd "$ROOT/tiffany/shim" && bash build.sh out )
cp "$ROOT/tiffany/shim/out/loader.Image" "$LOADER"

echo "=== ADT"
# D0 only exercises the loader: leave /product out and fix the random seed so the image
# stays byte-identical whether or not the (non-git) iPhone X device tree is present.
SEED=00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
python3 "$ROOT/tiffany/tools/mkadt_tiffany.py" "$OUT/tiffany.adt" --no-product --seed-hex "$SEED"

echo "=== payload (fakexnu) + boot image"
python3 "$ROOT/tiffany/tools/tiffany_pack.py" "$FAKE" "$OUT/tiffany-d0.img" \
	--loader "$LOADER" --dtb "$DTB" --no-product --seed-hex "$SEED" \
	--payload-out "$OUT/tiffany-d0.payload" \
	--cmdline "debug=0xc serial=3 cpus=1 keepsyms=1"

echo "=== boot image check"
python3 "$ROOT/tools/unpack_bootv2.py" "$OUT/tiffany-d0.img" "$OUT/check-d0" >/dev/null
cmp "$OUT/check-d0/ramdisk" "$OUT/tiffany-d0.payload"
echo "ramdisk == payload: OK"

echo "=== host loader test"
clang -O2 -g -DHOST -I "$ROOT/tiffany/shim" -o "$OUT/host_test_loader" \
	"$ROOT/tiffany/shim/host_test_loader.c" "$ROOT/tiffany/shim/loader.c" \
	"$ROOT/tiffany/shim/console.c" "$ROOT/tiffany/shim/fdt.c"
"$OUT/host_test_loader" "$OUT/tiffany-d0.payload" "$DTB" "$FAKE"

echo
echo "D0 ready: $OUT/tiffany-d0.img"
sha256sum "$OUT/tiffany-d0.img"
echo "Next: on Windows, in fastboot: fastboot boot tiffany-d0.img"
