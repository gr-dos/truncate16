#!/bin/sh
#
# Compare the Watcom truncate.exe with the assembly truncate.com: file
# size, FAT12 allocation on the standard floppy formats (measured by
# copying each file onto a freshly formatted image with mtools), and
# the conventional memory DOS needs to load and run each program.
#
# Usage: sh measure.sh path/to/truncate.exe path/to/truncate.com \
#            path/to/truncate.asm
# Environment: NASM (default nasm), used for the .COM's section sizes.

set -u
LC_ALL=C
export LC_ALL

usage='usage: measure.sh truncate.exe truncate.com truncate.asm'
exe=${1:?$usage}
com=${2:?$usage}
src=${3:?$usage}
NASM=${NASM:-nasm}
for t in mformat mcopy mdir minfo "$NASM"; do
    command -v "$t" >/dev/null || { echo "$t not found" >&2; exit 2; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/dostrunc.XXXXXX")
trap 'rm -rf "$work"' EXIT

size() { wc -c < "$1" | tr -d ' '; }

# u16 FILE OFFSET: little-endian word
u16() { od -A n -t u2 -j "$2" -N 2 "$1" | tr -d ' '; }

# free FORMAT [FILE]: bytes free on a fresh FORMAT (KB) image, after
# copying FILE onto it if given
free() {
    img=$work/f.img
    rm -f "$img"
    mformat -C -f "$1" -i "$img" :: >/dev/null || exit 2
    [ $# -lt 2 ] || mcopy -i "$img" "$2" ::X >/dev/null || exit 2
    mdir -i "$img" :: | sed -n 's/^ *\([0-9 ]*\) bytes free.*/\1/p' | tr -d ' '
}

# section sizes of the .COM, from a NASM map
version=$(cat "$(dirname "$src")/../VERSION")
"$NASM" -f bin "-DVERSION=\"$version\"" -o /dev/null \
    --before "[map sections $work/t.map]" "$src" || exit 2
# sect NAME FIELD: a field of the section summary (1 vstart, 4 length)
sect() {
    echo $((0x$(awk -v s="$1" -v f="$2" '$6 == s { print $f }' \
        "$work/t.map")))
}
text=$(sect .text 4)
data=$(sect .data 4)
bss=$(sect .bss 4)
bss_end=$(( $(sect .bss 1) - 0x100 + bss ))  # from the PSP's end
stack=$(sed -n 's/^STACK *equ *\([0-9]*\).*/\1/p' "$src")

echo "File size (bytes)"
printf '  %-13s %6d\n' truncate.exe "$(size "$exe")"
printf '  %-13s %6d  (%d code, %d data)\n' truncate.com "$(size "$com")" \
    $text $((data + $(size "$com") - text - data))

echo
echo "FAT12 allocation (bytes taken from a fresh floppy, clusters)"
printf '  %-8s %8s %18s %18s\n' format cluster truncate.exe truncate.com
for f in 360 720 1200 1440; do
    empty=$(free $f)
    used_e=$((empty - $(free $f "$exe")))
    used_c=$((empty - $(free $f "$com")))
    cl=$(minfo -i "$work/f.img" :: |
        sed -n 's/^cluster size: *\([0-9]*\).*/\1/p')
    cl=$((cl * 512))
    printf '  %-8s %8d %10d (%3d cl) %10d (%3d cl)\n' "${f}K" $cl \
        $used_e $((used_e / cl)) $used_c $((used_c / cl))
done

# MZ header: bytes in last page, pages, header paragraphs, min alloc
last=$(u16 "$exe" 2); pages=$(u16 "$exe" 4)
hdr=$(u16 "$exe" 8); minalloc=$(u16 "$exe" 10)
[ "$last" -eq 0 ] && last=512
image=$(( (pages - 1) * 512 + last - hdr * 16 ))
exe_min=$(( 256 + (image + 15) / 16 * 16 + minalloc * 16 ))

# a .COM has no header: it needs the PSP, the image, its uninitialised
# data and its stack (the program checks for this room at startup)
com_min=$(( 256 + bss_end + stack ))

echo
echo "Conventional memory needed to run (bytes, including the 256-byte PSP)"
printf '  %-13s %6d  (image %d + min alloc %d paragraphs)\n' \
    truncate.exe $exe_min $image $minalloc
printf '  %-13s %6d  (image %d + data %d + stack %d)\n' \
    truncate.com $com_min "$(size "$com")" $((bss_end - $(size "$com"))) \
    $stack
