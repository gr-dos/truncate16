#!/bin/sh
#
# Test truncate.exe under DOSBox-X.
#
# One batch file runs every DOS-side step, and the results are checked
# on the host afterwards.  Each step N records truncate's exit status in
# RN.TXT and its standard output in ON.TXT.  DOS cannot redirect
# standard error, so diagnostics are not checked.  rc.bat uses goto
# rather than "if errorlevel N echo ... >file" because the DOSBox-X
# shell opens the redirection even when the test is false.
#
# To add a test: add a step to steps.bat (command, then "call rc N")
# and the matching rc/expect/check lines below.
#
# Usage: tests/run.sh [path/to/truncate.exe]
# Environment: DOSBOX (default dosbox-x), KEEP=1 to keep the work
#              directory.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
exe=${1:-$top/truncate.exe}
DOSBOX=${DOSBOX:-dosbox-x}

command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
[ -f "$exe" ] || { echo "$exe not found" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/dostrunc.XXXXXX")
pass=0
fail=0
LC_ALL=C
export LC_ALL

# ------------------------------------------------------------------
# fixtures

cd "$work" || exit 2
cp "$exe" truncate.exe

# mkfile NAME SIZE: SIZE bytes of a repeating, non-zero pattern
mkfile() {
    yes 'abcdefghijklmnopqrstuvwxyz0123456789' | head -c "$2" > "$1"
}

mkfile SHRINK.DAT 1000
mkfile GROW.DAT 10
mkfile SAME.DAT 300
mkfile PLUS.DAT 100
mkfile MINUS.DAT 100
mkfile CLAMP.DAT 100
mkfile ATMOST1.DAT 100
mkfile ATMOST2.DAT 10
mkfile ATLEAST1.DAT 100
mkfile ATLEAST2.DAT 10
mkfile RDOWN.DAT 1000
mkfile RUP1.DAT 1000
mkfile RUP2.DAT 1024
mkfile NOCR.DAT 40
mkfile MULTI1.DAT 77
mkfile MULTI2.DAT 5
mkfile DASH.DAT 30
mkfile -DASH.DAT 30
mkfile BAD.DAT 50
mkfile ZT.DAT 50
mkfile ZQ.DAT 50
mkfile ZYB.DAT 50
mkfile ZEIB.DAT 50
mkfile RDONLY.DAT 200
chmod 444 RDONLY.DAT
: > EMPTY0.DAT
: > EMPTY1.DAT
: > EMPTY2.DAT
: > EMPTY3.DAT
# sparse on the host, so they take no disk space
truncate -s 2147483647 BIG1.DAT
truncate -s 2147483000 BIG2.DAT
truncate -s 2147483647 BIG3.DAT
truncate -s 2147483647 BIG4.DAT
truncate -s 2147483646 BIG5.DAT
truncate -s 2147483647 BIG6.DAT

cat > rc.bat <<'EOS'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >c:\r%1.txt
goto end
:rc1
echo rc1 >c:\r%1.txt
goto end
:rc2
echo rc2 >c:\r%1.txt
:end
EOS

cat > steps.bat <<'EOS'
@echo off
rem --- create, shrink, extend
truncate -s 100 new.dat >o1.txt
call rc 1
truncate -s 10 shrink.dat >o2.txt
call rc 2
truncate -s 50 grow.dat >o3.txt
call rc 3
truncate -s 300 same.dat >o4.txt
call rc 4
truncate -s 0 empty.dat >o5.txt
call rc 5
rem --- no create
truncate -c -s 10 nocr1.dat >o6.txt
call rc 6
truncate --no-create --size=10 nocr.dat >o7.txt
call rc 7
rem --- relative sizes
truncate -s +5 plus.dat >o8.txt
call rc 8
truncate -s -30 minus.dat >o9.txt
call rc 9
truncate -s -999 clamp.dat >o10.txt
call rc 10
truncate -s "<50" atmost1.dat >o11.txt
call rc 11
truncate -s "<50" atmost2.dat >o12.txt
call rc 12
truncate -s ">50" atleast1.dat >o13.txt
call rc 13
truncate -s ">50" atleast2.dat >o14.txt
call rc 14
truncate -s /256 rdown.dat >o15.txt
call rc 15
truncate -s %%256 rup1.dat >o16.txt
call rc 16
truncate -s %%256 rup2.dat >o17.txt
call rc 17
rem --- units and option forms
truncate -s 2K unitk.dat >o18.txt
call rc 18
truncate -s 2KB unitkb.dat >o19.txt
call rc 19
truncate -s 1KiB unitkib.dat >o20.txt
call rc 20
truncate -s1M unitm.dat >o21.txt
call rc 21
truncate --size 7 opt1.dat >o22.txt
call rc 22
truncate opt2.dat -cs12 >o23.txt
call rc 23
truncate -s 33 multi1.dat multi2.dat >o24.txt
call rc 24
truncate -s 3 -- -dash.dat dash.dat >o25.txt
call rc 25
rem --- help and version
truncate --help >o26.txt
call rc 26
truncate -h >o27.txt
call rc 27
truncate -? >o28.txt
call rc 28
truncate --version >o29.txt
call rc 29
rem --- errors
truncate bad.dat >o30.txt
call rc 30
truncate -s 5 >o31.txt
call rc 31
truncate -s 5x bad.dat >o32.txt
call rc 32
truncate -s /0 bad.dat >o33.txt
call rc 33
truncate -s 3G bad.dat >o34.txt
call rc 34
truncate --bogus -s 5 bad.dat >o35.txt
call rc 35
truncate -x -s 5 bad.dat >o36.txt
call rc 36
truncate bad.dat -s >o37.txt
call rc 37
truncate -s +2147483647 bad.dat >o38.txt
call rc 38
truncate -s 5 nodir\x.dat >o39.txt
call rc 39
rem --- zero with any unit
truncate -s 0T zt.dat >o40.txt
call rc 40
truncate -s 0Q zq.dat >o41.txt
call rc 41
truncate -s 0YB zyb.dat >o42.txt
call rc 42
truncate -s 0EiB zeib.dat >o43.txt
call rc 43
rem --- read-only files fail even when nothing would change (as GNU)
truncate -s ">100" rdonly.dat >o44.txt
call rc 44
truncate -c -s 10 rdonly.dat >o45.txt
call rc 45
rem --- later operands are processed after a failure
truncate -s 5 nodir\x.dat after1.dat rdonly.dat after2.dat >o46.txt
call rc 46
rem --- existing empty files
truncate -s 10 empty0.dat >o47.txt
call rc 47
truncate -s %%512 empty1.dat >o48.txt
call rc 48
truncate -s +0 empty2.dat >o49.txt
call rc 49
truncate -c -s -5 empty3.dat >o50.txt
call rc 50
rem --- arithmetic at the 2 GiB - 1 limit
truncate -s +1 big1.dat >o51.txt
call rc 51
truncate -s %%2000000000 big2.dat >o52.txt
call rc 52
truncate -s -1 big3.dat >o53.txt
call rc 53
truncate -s /1073741824 big4.dat >o54.txt
call rc 54
truncate -s +1 big5.dat >o55.txt
call rc 55
truncate -s 2147483647 big6.dat >o56.txt
call rc 56
truncate -s 2147483648 bad.dat >o57.txt
call rc 57
truncate -s 2GiB bad.dat >o58.txt
call rc 58
EOS

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "c:" \
    -c "steps.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks

ok()     { pass=$((pass + 1)); }
not_ok() { echo "FAIL: $*"; fail=$((fail + 1)); }

# check NAME COMMAND...
check() {
    name=$1
    shift
    if "$@"; then ok; else not_ok "$name"; fi
}

# rc STEP EXPECTED-STATUS
rc() {
    got=$(tr -d ' \r' < "R$1.TXT" 2>/dev/null | sed 's/^rc//')
    if [ "$got" = "$2" ]; then
        ok
    else
        not_ok "step $1: exit status ${got:-missing}, expected $2"
    fi
}

# expect STEP < expected-lines; compares ON.TXT with CRs removed
expect() {
    tr -d '\r' < "O$1.TXT" 2>/dev/null > got.txt
    cat > want.txt
    if cmp -s got.txt want.txt; then
        ok
    else
        not_ok "step $1: output differs"
        diff want.txt got.txt | sed 's/^/    /'
    fi
}

# size STEP FILE EXPECTED-SIZE
size() {
    if [ ! -f "$2" ]; then
        not_ok "step $1: $2 missing"
        return
    fi
    got=$(wc -c < "$2" | tr -d ' ')
    if [ "$got" = "$3" ]; then
        ok
    else
        not_ok "step $1: $2 is $got bytes, expected $3"
    fi
}

# content STEP FILE ORIGINAL-SIZE: the first min(size, ORIGINAL-SIZE)
# bytes are the fixture pattern and any bytes after them are zero
content() {
    n=$(wc -c < "$2" | tr -d ' ')
    keep=$3
    [ "$n" -lt "$keep" ] && keep=$n
    mkfile want.bin "$keep"
    head -c "$((n - keep))" /dev/zero >> want.bin
    check "step $1: $2 content" cmp -s want.bin "$2"
}

# create, shrink, extend
rc 1 0; expect 1 < /dev/null; size 1 NEW.DAT 100; content 1 NEW.DAT 0
rc 2 0; size 2 SHRINK.DAT 10;  content 2 SHRINK.DAT 1000
rc 3 0; size 3 GROW.DAT 50;    content 3 GROW.DAT 10
rc 4 0; size 4 SAME.DAT 300;   content 4 SAME.DAT 300
rc 5 0; size 5 EMPTY.DAT 0

# no create
rc 6 0; check "step 6: not created" test ! -e NOCR1.DAT
rc 7 0; size 7 NOCR.DAT 10;  content 7 NOCR.DAT 40

# relative sizes
rc 8 0;  size 8 PLUS.DAT 105;     content 8 PLUS.DAT 100
rc 9 0;  size 9 MINUS.DAT 70;     content 9 MINUS.DAT 100
rc 10 0; size 10 CLAMP.DAT 0
rc 11 0; size 11 ATMOST1.DAT 50
rc 12 0; size 12 ATMOST2.DAT 10
rc 13 0; size 13 ATLEAST1.DAT 100
rc 14 0; size 14 ATLEAST2.DAT 50; content 14 ATLEAST2.DAT 10
rc 15 0; size 15 RDOWN.DAT 768
rc 16 0; size 16 RUP1.DAT 1024;   content 16 RUP1.DAT 1000
rc 17 0; size 17 RUP2.DAT 1024

# units and option forms
rc 18 0; size 18 UNITK.DAT 2048
rc 19 0; size 19 UNITKB.DAT 2000
rc 20 0; size 20 UNITKIB.DAT 1024
rc 21 0; size 21 UNITM.DAT 1048576; content 21 UNITM.DAT 0
rc 22 0; size 22 OPT1.DAT 7
rc 23 0; check "step 23: -c not created" test ! -e OPT2.DAT
rc 24 0; size 24 MULTI1.DAT 33; size 24 MULTI2.DAT 33
rc 25 0; size 25 -DASH.DAT 3; size 25 DASH.DAT 3

# help and version
rc 26 0
check "step 26: help" grep -q '^Usage: truncate' O26.TXT
rc 27 0
check "step 27: -h same as --help" cmp -s O26.TXT O27.TXT
rc 28 0
check "step 28: -? same as --help" cmp -s O26.TXT O28.TXT
rc 29 0
expect 29 <<EOS
truncate (dos-truncate16) $(cat "$top/VERSION")
EOS

# errors: nothing on stdout, exit 1, BAD.DAT untouched
for n in 30 31 32 33 34 35 36 37 38 39; do
    rc $n 1
    expect $n < /dev/null
done
size 30 BAD.DAT 50
check "step 31: no file created" test ! -e 5

# zero with any unit
for n in 40 41 42 43; do rc $n 0; done
size 40 ZT.DAT 0; size 41 ZQ.DAT 0; size 42 ZYB.DAT 0; size 43 ZEIB.DAT 0

# read-only files (root ignores the permission, so skip there)
if [ "$(id -u)" != 0 ]; then
    rc 44 1; size 44 RDONLY.DAT 200
    rc 45 1; size 45 RDONLY.DAT 200
    rc 46 1
fi
size 46 AFTER1.DAT 5; size 46 AFTER2.DAT 5

# existing empty files
rc 47 0; size 47 EMPTY0.DAT 10; content 47 EMPTY0.DAT 0
rc 48 0; size 48 EMPTY1.DAT 0
rc 49 0; size 49 EMPTY2.DAT 0
rc 50 0; size 50 EMPTY3.DAT 0

# arithmetic at the 2 GiB - 1 limit
rc 51 1; size 51 BIG1.DAT 2147483647
rc 52 1; size 52 BIG2.DAT 2147483000
rc 53 0; size 53 BIG3.DAT 2147483646
rc 54 0; size 54 BIG4.DAT 1073741824
rc 55 0; size 55 BIG5.DAT 2147483647
rc 56 0; size 56 BIG6.DAT 2147483647
rc 57 1; rc 58 1; size 58 BAD.DAT 50

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
