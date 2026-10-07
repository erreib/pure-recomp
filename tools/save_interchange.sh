#!/bin/bash
# Save interchange with PPSSPP (task 045): saves move both ways between the port and a PSP (PPSSPP stands in for one)
# now that the port writes them in the save-data utility's no-key mode, mode 1, as a PSP does (patch 0019).
#   (a) PPSSPP -> port  PPSSPP's profile (ref/saves/ppsspp/UCUS98612P0000: NAME0000, AAA, made by the driver's
#                       frontend.txt + save_yes.txt + save_dialog.txt) on a fresh memory stick of the port's; the
#                       port runs config/pad_scripts/profile_load.txt headless with PURE_TRACE_SAVEDATA: LISTLOAD
#                       loads it with both hashes verified, MAIN MENU matches the suite's reference, SET NAME shows
#                       NAME0000, and the game's own PROFILE > SAVE (the script's `save P0000`) writes it back in
#                       mode 1 with "User name: NAME0000" in PARAM.SFO. That save is the round trip's.
#   plain               a plain save the build before patch 0019 wrote (ref/saves/port-plain/UCUS98612P0000) loads the
#                       same way, and the game's PROFILE > SAVE rewrites it in mode 1.
#   born                the port's own profile: main_menu.txt on an empty stick, headless (the same presses that made
#                       PPSSPP's), for (c).
#   (b) port -> PPSSPP  the round trip's save copied into PPSSPP's memory stick: tools/ppsspp/routes/profile_load.txt
#                       picks it in PPSSPP's LOAD dialog ("Load completed."), MAIN MENU matches the reference, and
#                       SET NAME shows NAME0000. Afterwards the save is moved out of PPSSPP's stick again and anything
#                       the script moved aside is put back, so the stick is left as it was found (other routes and
#                       the scorecard expect no UCUS98612P* there).
#   (c) the saves side by side, each through the framework's own load path (load_save) and hash checks, built from
#                       vendor/portablekit into out/045/savecheck: the port's own profile and the round trip's against
#                       PPSSPP's, and the first-boot PPCD00001DLS001 of each. PARAM.SFO's fields and flag byte must be
#                       equal apart from the two hashes that cover the random header; the other files byte-equal; the
#                       decrypted contents are compared and every difference listed (words holding guest addresses
#                       are named as such).
# PASS when (a), plain and (b) load and (c) verifies both sides. About 3 minutes: the port runs are headless and
# unpaced (seconds each), the PPSSPP run real-time (about 80 s). Logs and captures in out/045/. No key value is read,
# printed or written: the checker asks the framework's crypto_keys() for its keys by slot, as the port does.
#   tools/save_interchange.sh                       the whole check
#   tools/save_interchange.sh --port-only           everything but (b), while PPSSPP is busy elsewhere: exit 3, never PASS
#   tools/save_interchange.sh --check FOLDER FILE [PLAIN_OUT]
#                                                   one save folder through the framework's load path: its flag, the
#                                                   hash checks, and the decrypted FILE written to PLAIN_OUT
#   tools/save_interchange.sh --make-ppsspp-save    remake ref/saves/ppsspp/UCUS98612P0000 with the driver (the stick
#                                                   must hold no UCUS98612P*); then update the hashes in ref/README.md
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=out/045
VENDOR=vendor/portablekit
PPSSPP_SAVEDATA="$HOME/.config/ppsspp/PSP/SAVEDATA"
PROFILE=UCUS98612P0000
DLS=PPCD00001DLS001
NAME=NAME0000
REF_PPSSPP=ref/saves/ppsspp
REF_PLAIN=ref/saves/port-plain
DIGITS=200,92,115,26     # PSP pixels: SET NAME's 5th to 8th letters, blank for the default "NAME" (save_roundtrip.sh)
MIN_NAME_VARIANCE=500    # 1545 with NAME0000 loaded in the port, 0 on an empty stick (task 014)
CHECKER="$OUT/savecheck/savecheck"
R=tools/ppsspp/routes

# --- the checker: the framework's save-data code and nothing else -------------------------------------------------
build_checker() {
  local src="$OUT/savecheck/savecheck.cpp"
  mkdir -p "$OUT/savecheck"
  cat > "$src.new" <<'EOF'
// One save folder through PortableKit's own load path (save_data/savedata_store.cpp, load_save) and its hash checks
// (save_data/savedata_crypto.cpp). Built by tools/save_interchange.sh. Prints no key and no hash value.
#include "crypto_keys.hpp"
#include "save_data/param_sfo.hpp"
#include "save_data/savedata_crypto.hpp"
#include "save_data/savedata_store.hpp"

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using namespace portablekit::savedata;

static std::vector<std::uint8_t> read_all(const fs::path &path) {
    std::ifstream in(path, std::ios::binary);
    return std::vector<std::uint8_t>(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

int main(int argc, char **argv) {
    if (argc < 4) {
        std::fprintf(stderr, "usage: savecheck FOLDER FILE STICK_DIR [PLAIN_OUT]\n");
        return 2;
    }
    const fs::path folder = fs::absolute(argv[1]);
    const std::string file = argv[2];
    // load_save reads <stick>/PSP/SAVEDATA/<game><save>: a stick of one folder, a link to the one checked.
    const fs::path stick = argv[3];
    const std::string name = folder.filename().string();
    fs::remove_all(stick);
    fs::create_directories(stick / "PSP" / "SAVEDATA");
    fs::create_directory_symlink(folder, stick / "PSP" / "SAVEDATA" / name);
    std::printf("keys %s\n", portablekit::savedata_keys_available() ? "available" : "MISSING");

    const auto sfo_bytes = read_all(folder / "PARAM.SFO");
    const auto sfo = ParamSfo::parse(sfo_bytes);
    if (!sfo) {
        std::printf("PARAM.SFO unreadable\nverdict FAIL\n");
        return 1;
    }
    const auto *params = sfo->binary("SAVEDATA_PARAMS");
    const std::uint8_t flags = params != nullptr && !params->empty() ? (*params)[0] : 0u;
    std::printf("flag 0x%02x (%s)\n", flags,
                flags == 0u ? "plain" : flags == 0x01u ? "mode 1" : flags == 0x21u ? "mode 3" : flags == 0x41u ? "mode 5" : "unknown");
    bool ok = true;
    if (flags != 0u) {
        const auto offset = sfo->data_offset("SAVEDATA_PARAMS");
        const bool sfo_ok = offset && verify_param_sfo(sfo_bytes, *offset);
        std::printf("PARAM.SFO hash (SAVEDATA_PARAMS) %s\n", sfo_ok ? "verified" : "FAILS");
        ok = ok && sfo_ok;
        const auto data = read_all(folder / file);
        bool listed = false;
        if (const auto *list = sfo->binary("SAVEDATA_FILE_LIST"))
            for (std::size_t at = 0; at + 32u <= list->size(); at += 32u) {
                const std::string entry(reinterpret_cast<const char *>(list->data() + at),
                                        strnlen(reinterpret_cast<const char *>(list->data() + at), 13u));
                if (entry != file) continue;
                listed = true;
                Block expected{};
                std::copy_n(list->begin() + static_cast<std::ptrdiff_t>(at + 13u), 16, expected.begin());
                const auto mode = mode_from_flags(flags);
                const bool file_ok = mode && *mode == CryptMode::Mode1 && data_file_hash(data, *mode, nullptr) == expected;
                std::printf("%s hash (SAVEDATA_FILE_LIST) %s, %zu bytes\n", file.c_str(),
                            file_ok ? "verified" : (mode && *mode != CryptMode::Mode1 ? "not checked (game key)" : "FAILS"),
                            data.size());
                ok = ok && file_ok;
            }
        if (!listed) {
            std::printf("%s not listed in SAVEDATA_FILE_LIST\n", file.c_str());
            ok = false;
        }
    }
    SaveFiles files;
    files.game_name = name;
    files.file_name = file;
    const LoadResult loaded = load_save(stick, files);
    const char *status = loaded.status == LoadStatus::Ok ? "ok" : loaded.status == LoadStatus::Broken ? "broken" : "no data";
    std::printf("load_save %s%s%s, %zu bytes%s\n", status, loaded.reason.empty() ? "" : ": ", loaded.reason.c_str(),
                loaded.contents.data.size(),
                loaded.status == LoadStatus::Ok && loaded.flags != 0u
                    ? (loaded.file_hash_checked ? " (decrypted, file hash checked)" : " (decrypted, no file hash)")
                    : "");
    ok = ok && loaded.status == LoadStatus::Ok;
    if (argc > 4 && loaded.status == LoadStatus::Ok) {
        std::ofstream out(argv[4], std::ios::binary);
        out.write(reinterpret_cast<const char *>(loaded.contents.data.data()),
                  static_cast<std::streamsize>(loaded.contents.data.size()));
    }
    fs::remove_all(stick);
    std::printf("verdict %s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
EOF
  if ! cmp -s "$src.new" "$src"; then mv "$src.new" "$src"; else rm -f "$src.new"; fi
  local sources=("$VENDOR/third_party/tiny_aes/aes.c" "$VENDOR/host/save_data/aes128.cpp"
                 "$VENDOR/host/save_data/param_sfo.cpp" "$VENDOR/host/save_data/savedata_crypto.cpp"
                 "$VENDOR/host/save_data/savedata_store.cpp" "$VENDOR/host/crypto_keys_builtin.cpp")
  local stale=0 f
  [ -x "$CHECKER" ] || stale=1
  for f in "$src" "${sources[@]}" "$VENDOR"/host/save_data/*.hpp "$VENDOR/host/crypto_keys.hpp"; do
    [ "$f" -nt "$CHECKER" ] && stale=1
  done
  [ $stale -eq 0 ] && return 0
  /usr/bin/clang++ -std=c++20 -O1 -w -I "$VENDOR/host" -I "$VENDOR/include" -I "$VENDOR/third_party" \
    -x c++ "$VENDOR/third_party/tiny_aes/aes.c" -x none "$src" "${sources[@]:1}" -o "$CHECKER" \
    > "$OUT/savecheck/build.log" 2>&1 || { echo "the checker does not build: $OUT/savecheck/build.log"; return 1; }
}

# check FOLDER FILE [PLAIN_OUT]: the checker's report, indented; exit code its verdict.
check() {
  "$CHECKER" "$1" "$2" "$OUT/savecheck/stick" ${3:+"$3"} | sed 's/^/          /'
  return "${PIPESTATUS[0]}"
}

if [ "${1:-}" = --check ]; then
  [ $# -ge 3 ] || { echo "usage: tools/save_interchange.sh --check FOLDER FILE [PLAIN_OUT]"; exit 2; }
  build_checker || exit 2
  "$CHECKER" "$2" "$3" "$OUT/savecheck/stick" ${4:+"$4"}
  exit $?
fi

# --- PPSSPP: one instance, one memory stick, shared with other work --------------------------------------------------
# wait_ppsspp: until no PPSSPPSDL runs (another worker's run is never touched), at most 20 minutes.
wait_ppsspp() {
  local waited=0
  while pgrep -x PPSSPPSDL > /dev/null; do
    [ $waited -eq 0 ] && echo "        PPSSPP is busy (pid $(pgrep -x PPSSPPSDL | tr '\n' ' ')); waiting"
    [ $waited -ge 1200 ] && return 1
    sleep 15; waited=$((waited + 15))
  done
  return 0
}

# ppsspp_run LOG ARGS...: one driver run; retried (after a wait) when another PPSSPP got there first.
ppsspp_run() {
  local log=$1; shift
  local try
  for try in 1 2 3; do
    wait_ppsspp || { echo "        PPSSPP stayed busy for 20 minutes"; return 1; }
    python3 tools/ppsspp/ppsspp_ctl.py run "$@" > "$log" 2>&1 && return 0
    grep -q "already running" "$log" || return 1
  done
  return 1
}

if [ "${1:-}" = --make-ppsspp-save ]; then
  mkdir -p "$OUT/make"
  ls -d "$PPSSPP_SAVEDATA"/UCUS98612P* > /dev/null 2>&1 &&
    { echo "PPSSPP's memory stick holds a profile save already ($PPSSPP_SAVEDATA); move it away first"; exit 1; }
  wait_ppsspp || exit 1
  python3 tools/ppsspp/ppsspp_ctl.py run --pad-file $R/frontend.txt --pad-file $R/save_yes.txt \
    --pad-file $R/save_dialog.txt --until 5700 --shot 5240:$OUT/make/save-dialog.png \
    --shot 5300:$OUT/make/save-completed.png --shot 5660:$OUT/make/main-menu.png > "$OUT/make/ppsspp.log" 2>&1
  rc=$?
  if [ -d "$PPSSPP_SAVEDATA/$PROFILE" ]; then
    rm -rf "$REF_PPSSPP/$PROFILE"; mkdir -p "$REF_PPSSPP"
    mv "$PPSSPP_SAVEDATA/$PROFILE" "$REF_PPSSPP/$PROFILE"
    [ -d "$REF_PPSSPP/$DLS" ] || cp -Rp "$PPSSPP_SAVEDATA/$DLS" "$REF_PPSSPP/$DLS"
    echo "PPSSPP's save moved to $REF_PPSSPP/$PROFILE (driver exit $rc); its SHA-256:"
    shasum -a 256 "$REF_PPSSPP/$PROFILE"/* "$REF_PPSSPP/$DLS"/*
    exit 0
  fi
  echo "PPSSPP wrote no $PROFILE (driver exit $rc, $OUT/make/ppsspp.log)"; exit 1
fi

# --- the check ------------------------------------------------------------------------------------------------------
PORT_ONLY=0
[ "${1:-}" = --port-only ] && PORT_ONLY=1
[ -x build/arm64/bin/PureNative ] || { echo "build/arm64/bin/PureNative missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }
for need in "$REF_PPSSPP/$PROFILE/PROFILE.BIN" "$REF_PPSSPP/$DLS/DATA1.BIN" "$REF_PLAIN/$PROFILE/PROFILE.BIN"; do
  [ -f "$need" ] || { echo "$need missing: ref/README.md, \"Saves (task 045)\", says how it was made"; exit 2; }
done

rm -rf "$OUT/a" "$OUT/plain" "$OUT/born" "$OUT/b" "$OUT/c" "$OUT/port-roundtrip"
mkdir -p "$OUT"
build_checker || exit 2
TOTAL=0
FAILS=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
verdict() { [ $FAILS -eq 0 ] && echo "PASS: $1" || echo "FAIL ($FAILS checks, see above)"; }
declare -a OUTCOME

echo "reference saves (SHA-256 as listed in ref/README.md):"
for f in "$REF_PPSSPP/$PROFILE"/* "$REF_PPSSPP/$DLS"/* "$REF_PLAIN/$PROFILE"/*; do
  sha=$(shasum -a 256 "$f" | cut -c1-64)
  grep -q "$sha" ref/README.md && echo "  ok    $f" || echo "  note  $f: $sha is not the one ref/README.md lists"
done

# stick NAME [FOLDER...]: a fresh memory stick out/045/NAME/game with these save folders on it.
stick() {
  local name=$1; shift
  local game="$OUT/$name/game"
  mkdir -p "$game/ms0/PSP/SAVEDATA"
  ln -sfn "$ROOT/game/EBOOT.ELF" "$game/EBOOT.ELF"
  ln -sfn "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' game/disc.iso)" "$game/disc.iso"
  local f
  for f in "$@"; do cp -Rp "$f" "$game/ms0/PSP/SAVEDATA/"; done
}

# port NAME SCRIPT FRAMES: a headless, silent, unpaced run on that stick (Metal backend for the shots).
port() {
  local name=$1 script=$2 frames=$3
  python3 tools/run_boot.py --shell headless --backend metal --script "$script" --shots "$OUT/$name/shots" \
    --frames "$frames" --seconds 300 --data-dir out/data/save_interchange \
    --env PURE_GAME_DIR="$ROOT/$OUT/$name/game" --env PURE_TRACE_SAVEDATA=1 "$OUT/$name/run.log" \
    > "$OUT/$name/run.stdout" 2>&1
  local rc=$?
  if [ $rc -eq 0 ] && grep -q "^\[pure\] exit at frame $frames" "$OUT/$name/run.log"; then
    ok "port run $name: $(basename "$script") headless to frame $frames"
  else
    bad "port run $name ended early (run_boot exit $rc; $OUT/$name/run.stdout)"
  fi
}

variance() {
  [ -f "$1" ] || { echo -1; return; }
  python3 tools/imgdiff.py "$1" --min-variance 0 --region "$DIGITS" --json |
    python3 -c 'import json, sys; print(int(json.load(sys.stdin)["max_variance"]))'
}

# shots_check DIR MENU NAME: MAIN MENU against the suite's reference (tol 24, limit 0.05 as frame_regress's
# main_menu) and SET NAME showing the loaded name.
shots_check() {
  local menu=$1 name=$2 who=$3
  if python3 tools/imgdiff.py "$menu" ref/main_menu.png --tol 24 --max-frac 0.05 > "$menu.txt" 2>&1; then
    ok "$who MAIN MENU matches ref/main_menu.png ($(cut -d' ' -f1-3 "$menu.txt"))"
  else
    bad "$who MAIN MENU: $(head -1 "$menu.txt") ($menu)"
  fi
  local v; v=$(variance "$name")
  if [ "$v" -ge "$MIN_NAME_VARIANCE" ]; then ok "$who SET NAME shows the loaded name past NAME (variance $v >= $MIN_NAME_VARIANCE)"
  else bad "$who SET NAME ($name): variance $v < $MIN_NAME_VARIANCE, the loaded name is not there"; fi
}

# load_run NAME: the LISTLOAD of P0000 and the game's PROFILE > SAVE back into it, in mode 1.
load_run() {
  local name=$1 kind=$2 log="$OUT/$1/run.log"
  local loaded; loaded=$(grep -m1 "^\[savedata\] loaded [0-9]* bytes from .*/$PROFILE\$" "$log" | sed "s|$ROOT/||")
  if [ -n "$loaded" ]; then ok "LISTLOAD: ${loaded#\[savedata\] }"; else bad "no load of $PROFILE in $log"; fi
  if [ "$kind" = mode1 ]; then
    grep -q "^\[savedata\] PROFILE.BIN: mode 1 (no game key), PARAM.SFO's hash verified, the file's hash in SAVEDATA_FILE_LIST verified, decrypted" "$log" &&
      ok "the port verified both hashes and decrypted it (mode 1)" || bad "no verified mode-1 load in $log"
  else
    grep -q "^\[savedata\] PROFILE.BIN: plain (SAVEDATA_PARAMS flag 0)" "$log" &&
      ok "loaded as a plain save (flag 0)" || bad "no plain load in $log"
  fi
  grep -q "^\[savedata\] broken save" "$log" && bad "$(grep -m1 "^\[savedata\] broken save" "$log" | sed "s|$ROOT/||")"
  shots_check "$OUT/$name/shots/menu-loaded.png" "$OUT/$name/shots/name-loaded.png" "port:"
  if grep -q "^\[savedata\] PROFILE.BIN: mode 1 (no game key), 41586 bytes, its hash in SAVEDATA_FILE_LIST, PARAM.SFO signed" "$log" &&
     [ "$(grep -c "^\[savedata\] saved [0-9]* bytes to .*/$PROFILE\$" "$log")" -ge 1 ]; then
    ok "the game's PROFILE > SAVE wrote $PROFILE back in mode 1 (41586 bytes)"
  else
    bad "no mode-1 save of $PROFILE in $log"
  fi
  local detail
  detail=$(python3 - "$OUT/$name/game/ms0/PSP/SAVEDATA/$PROFILE/PARAM.SFO" <<'EOF'
import struct, sys
d = open(sys.argv[1], "rb").read()
kt, vt, n = struct.unpack_from("<III", d, 8)
for i in range(n):
    ko, fmt, ln, mx, vo = struct.unpack_from("<HHIII", d, 20 + i * 16)
    if d[kt + ko:d.index(b"\0", kt + ko)] == b"SAVEDATA_DETAIL":
        print(d[vt + vo:vt + vo + ln].split(b"\0")[0].decode("latin-1").split("\n")[0].strip())
EOF
)
  [ "$detail" = "User name: $NAME" ] && ok "the game's own profile line in the save it wrote: \"$detail\"" ||
    bad "the save the game wrote names \"$detail\", not $NAME"
  if check "$OUT/$name/game/ms0/PSP/SAVEDATA/$PROFILE" PROFILE.BIN "$OUT/$name/profile.plain"; then
    ok "the port's save verifies under the framework's checks"
  else
    bad "the port's save does not verify"
  fi
}

# 1. (a) PPSSPP -> port.
echo
echo "(a) PPSSPP's profile on the port's memory stick"
FAILS=0
check "$REF_PPSSPP/$PROFILE" PROFILE.BIN "$OUT/ppsspp-profile.plain" &&
  ok "PPSSPP's save verifies under the framework's checks" || bad "PPSSPP's save does not verify (escalate: report the hash inputs, never values)"
stick a "$REF_PPSSPP/$PROFILE"
port a config/pad_scripts/profile_load.txt 3900
load_run a mode1
mkdir -p "$OUT/port-roundtrip" && cp -Rp "$OUT/a/game/ms0/PSP/SAVEDATA/$PROFILE" "$OUT/port-roundtrip/"
OUTCOME[1]="(a) PPSSPP -> port: $(verdict "PPSSPP's NAME0000 loaded (PARAM.SFO and PROFILE.BIN hashes verified), MAIN MENU and SET NAME as on PPSSPP; the game saved it back in mode 1")"
TOTAL=$((TOTAL + FAILS))

# 2. A plain save from the build before patch 0019.
echo
echo "plain: the previous build's plain save"
FAILS=0
check "$REF_PLAIN/$PROFILE" PROFILE.BIN && ok "the plain save reads through the framework's load path (flag 0, nothing to verify)" ||
  bad "the plain save does not read"
stick plain "$REF_PLAIN/$PROFILE"
port plain config/pad_scripts/profile_load.txt 3900
load_run plain plain
OUTCOME[2]="plain save: $(verdict "the previous build's plain NAME0000 loaded and showed; the game's PROFILE > SAVE rewrote it in mode 1")"
TOTAL=$((TOTAL + FAILS))

# 3. The port's own profile, for (c).
echo
echo "born: the port's own NAME0000 (main_menu.txt on an empty stick)"
FAILS=0
stick born
cat config/pad_scripts/main_menu.txt > "$OUT/born/route.txt"
echo "2250:shot fresh-name" >> "$OUT/born/route.txt"   # SET NAME on the empty stick, "NAME": the control (014's)
port born "$OUT/born/route.txt" 4800
v_fresh=$(variance "$OUT/born/shots/fresh-name.png")
if [ "$v_fresh" -ge 0 ] && [ "$v_fresh" -lt 50 ]; then ok "control: SET NAME on the empty stick is blank past NAME (variance $v_fresh)"
else bad "control capture $OUT/born/shots/fresh-name.png: variance $v_fresh (want 0 to 49)"; fi
grep -q "^\[savedata\] PROFILE.BIN: mode 1 (no game key), 41586 bytes" "$OUT/born/run.log" &&
  ok "NEW wrote $PROFILE in mode 1" || bad "no mode-1 NEW save in $OUT/born/run.log"
grep -q "^\[savedata\] DATA1.BIN: mode 1 (no game key), 784 bytes" "$OUT/born/run.log" &&
  ok "the first-boot AUTOSAVE wrote $DLS in mode 1" || bad "no mode-1 AUTOSAVE of $DLS in $OUT/born/run.log"
OUTCOME[3]="born: $(verdict "the port's NEW profile and first-boot autosave written in mode 1")"
TOTAL=$((TOTAL + FAILS))

# 4. (b) port -> PPSSPP.
echo
echo "(b) the port's save (the round trip's) in PPSSPP"
FAILS=0
mkdir -p "$OUT/b/stick-before" "$OUT/b/shots"
restore_stick() {
  # The save this script put on PPSSPP's stick comes out again, and whatever was moved aside goes back.
  if [ -f "$OUT/b/copied" ] && [ -d "$PPSSPP_SAVEDATA/$PROFILE" ]; then
    mkdir -p "$OUT/b/after"; rm -rf "$OUT/b/after/$PROFILE"
    mv "$PPSSPP_SAVEDATA/$PROFILE" "$OUT/b/after/$PROFILE"
    rm -f "$OUT/b/copied"
  fi
  local f
  for f in "$OUT/b/stick-before"/*; do
    [ -e "$f" ] && [ ! -e "$PPSSPP_SAVEDATA/$(basename "$f")" ] && mv "$f" "$PPSSPP_SAVEDATA/"
  done
}
trap restore_stick EXIT
trap 'restore_stick; exit 130' INT TERM
if [ $PORT_ONLY -eq 1 ]; then
  echo "        not run (--port-only)"
elif [ -d "$PPSSPP_SAVEDATA" ]; then
  found=$(ls "$PPSSPP_SAVEDATA" | sort | tr '\n' ' ')
  for f in "$PPSSPP_SAVEDATA"/UCUS98612P*; do
    [ -e "$f" ] || continue
    echo "        PPSSPP's stick holds $(basename "$f"); moved aside to $OUT/b/stick-before/ and put back afterwards"
    mv "$f" "$OUT/b/stick-before/"
  done
  wait_ppsspp
  cp -Rp "$OUT/port-roundtrip/$PROFILE" "$PPSSPP_SAVEDATA/$PROFILE" && touch "$OUT/b/copied"
  before=$(cd "$PPSSPP_SAVEDATA/$PROFILE" && shasum -a 256 * | shasum -a 256 | cut -c1-16)
  if ppsspp_run "$OUT/b/ppsspp.log" --pad-file $R/profile_load.txt --until 4600 \
       --shot 3000:$OUT/b/shots/load-list.png --shot 3150:$OUT/b/shots/load-completed.png \
       --shot 3720:$OUT/b/shots/menu-loaded.png --shot 4560:$OUT/b/shots/name-loaded.png \
       --report "$OUT/b/ppsspp.json"; then
    ok "PPSSPP ran tools/ppsspp/routes/profile_load.txt to frame 4600"
  else
    bad "the PPSSPP run failed ($OUT/b/ppsspp.log)"
  fi
  after=$(cd "$PPSSPP_SAVEDATA/$PROFILE" 2>/dev/null && shasum -a 256 * | shasum -a 256 | cut -c1-16)
  [ "$before" = "$after" ] && ok "PPSSPP left the save as it was (read only)" || echo "        note  PPSSPP rewrote the save"
  shots_check "$OUT/b/shots/menu-loaded.png" "$OUT/b/shots/name-loaded.png" "PPSSPP:"
  # The name itself: PPSSPP's SET NAME against the port's in (a) (the same NAME0000), and against the port's empty
  # stick ("NAME"), the control.
  if python3 tools/imgdiff.py "$OUT/b/shots/name-loaded.png" "$OUT/a/shots/name-loaded.png" --tol 24 --max-frac 0.02 \
       > "$OUT/b/name.txt" 2>&1; then
    ok "PPSSPP's SET NAME equals the port's with PPSSPP's save, NAME0000 ($(cut -d' ' -f1-3 "$OUT/b/name.txt"))"
  else
    bad "PPSSPP's SET NAME against the port's in (a): $(head -1 "$OUT/b/name.txt")"
  fi
  python3 tools/imgdiff.py "$OUT/b/shots/name-loaded.png" "$OUT/born/shots/fresh-name.png" --region "$DIGITS" --tol 24 \
    --max-frac 0.05 > "$OUT/b/control.txt" 2>&1
  [ $? -eq 1 ] && ok "and differs from SET NAME on an empty stick past NAME ($(cut -d' ' -f1-3 "$OUT/b/control.txt"))" ||
    bad "PPSSPP's SET NAME is not told apart from the empty stick's: $(head -1 "$OUT/b/control.txt")"
  restore_stick
  left=$(ls "$PPSSPP_SAVEDATA" | sort | tr '\n' ' ')
  if [ "$left" = "$found" ]; then ok "PPSSPP's stick left as it was found ($found)"
  else bad "PPSSPP's stick holds $left, not $found as before"; fi
else
  bad "no PPSSPP memory stick at $PPSSPP_SAVEDATA"
fi
[ $PORT_ONLY -eq 1 ] && OUTCOME[4]="(b) port -> PPSSPP: NOT RUN (--port-only)" ||
OUTCOME[4]="(b) port -> PPSSPP: $(verdict "PPSSPP loaded the port's mode-1 NAME0000 (Load completed., MAIN MENU, SET NAME shows NAME0000)")"
TOTAL=$((TOTAL + FAILS))

# 5. (c) the saves side by side.
echo
echo "(c) the port's saves against PPSSPP's"
FAILS=0
mkdir -p "$OUT/c"
compare() {
  local label=$1 port_dir=$2 ppsspp_dir=$3 file=$4
  echo "  $label"
  echo "        PPSSPP: $ppsspp_dir"
  check "$ppsspp_dir" "$file" "$OUT/c/$label.ppsspp.plain" || bad "$label: PPSSPP's does not verify"
  echo "        port:   $port_dir"
  check "$port_dir" "$file" "$OUT/c/$label.port.plain" || bad "$label: the port's does not verify"
  python3 - "$port_dir" "$ppsspp_dir" "$file" "$OUT/c/$label.port.plain" "$OUT/c/$label.ppsspp.plain" <<'EOF'
import os, struct, sys
port_dir, pp_dir, data_file, port_plain, pp_plain = sys.argv[1:6]
fails = 0
def ok(m): print("  ok    " + m)
def bad(m):
    global fails
    fails += 1
    print("  FAIL  " + m)

def sfo(path):
    d = open(path, "rb").read()
    kt, vt, n = struct.unpack_from("<III", d, 8)
    entries = []
    for i in range(n):
        ko, fmt, ln, mx, vo = struct.unpack_from("<HHIII", d, 20 + i * 16)
        entries.append((d[kt + ko:d.index(b"\0", kt + ko)].decode(), fmt, ln, mx, vt + vo, d[vt + vo:vt + vo + ln]))
    return d, entries

# The bytes that cover the data file's random header: its hash in SAVEDATA_FILE_LIST (13 to 28 of its entry) and
# the mode-1 hash of PARAM.SFO (SAVEDATA_PARAMS 0x10 to 0x1F), which covers the list.
a, ea = sfo(os.path.join(port_dir, "PARAM.SFO"))
b, eb = sfo(os.path.join(pp_dir, "PARAM.SFO"))
if len(a) != len(b) or [e[:5] for e in ea] != [e[:5] for e in eb]:
    bad(f"PARAM.SFO layouts differ ({len(a)} and {len(b)} bytes)")
else:
    expected = set()
    for name, fmt, ln, mx, at, value in eb:
        if name == "SAVEDATA_PARAMS":
            expected.update(range(at + 0x10, at + 0x20))
        if name == "SAVEDATA_FILE_LIST":
            for e in range(0, ln, 32):
                if value[e:e + 13].split(b"\0")[0]:
                    expected.update(range(at + e + 13, at + e + 29))
    other = []
    for name, fmt, ln, mx, at, value in ea:
        diff = [i for i in range(at, at + ln) if a[i] != b[i]]
        unexplained = [i for i in diff if i not in expected]
        if unexplained:
            other.append(f"{name} (bytes {', '.join(str(i - at) for i in unexplained[:8])})")
    head = [i for i in range(len(a)) if a[i] != b[i] and not any(e[4] <= i < e[4] + e[2] for e in ea)]
    if head:
        other.append(f"the header or key table (bytes {head[:8]})")
    params = dict((e[0], e[5]) for e in eb)["SAVEDATA_PARAMS"]
    port_params = dict((e[0], e[5]) for e in ea)["SAVEDATA_PARAMS"]
    print(f"        PARAM.SFO {len(a)} bytes each, the same keys, formats and lengths; flag byte 0x{port_params[0]:02x} (port) "
          f"and 0x{params[0]:02x} (PPSSPP)")
    if other:
        bad("PARAM.SFO differs beyond the hashes: " + "; ".join(other))
    else:
        strings = {e[0]: e[5].split(b"\0")[0].decode("latin-1") for e in ea if e[1] == 0x0204}
        ok("PARAM.SFO's fields equal (" + ", ".join(f"{k}" for k in strings) + ", PARENTAL_LEVEL, the file list's names, "
           "SAVEDATA_PARAMS's flag and console slot); only the header-dependent hashes differ")
    (ok if port_params[:16] == params[:16] else bad)("SAVEDATA_PARAMS's first 16 bytes (the flag byte) equal")

# The utility's other files must be the same bytes; a file the game writes itself through sceIo (DLS001's
# DATA2.BIN) is not the utility's, and is only reported.
others = sorted(set(os.listdir(pp_dir)) | set(os.listdir(port_dir)))
same, differ, own = [], [], []
for f in others:
    if f in ("PARAM.SFO", data_file):
        continue
    pa, pb = os.path.join(port_dir, f), os.path.join(pp_dir, f)
    equal = os.path.exists(pa) and os.path.exists(pb) and open(pa, "rb").read() == open(pb, "rb").read()
    if f not in ("ICON0.PNG", "ICON1.PMF", "PIC1.PNG", "SND0.AT3"):
        if equal:
            own.append(f"{f} equal")
        elif os.path.exists(pa) and os.path.exists(pb):
            x, y = open(pa, "rb").read(), open(pb, "rb").read()
            n = sum(1 for i in range(min(len(x), len(y))) if x[i] != y[i])
            own.append(f"{f} differs in {n} of {len(y)} bytes")
        else:
            own.append(f"{f} on one side only")
    elif equal:
        same.append(f)
    else:
        differ.append(f)
if differ:
    bad("the utility's other files differ: " + ", ".join(differ))
else:
    ok("the utility's other files byte-equal: " + (", ".join(same) if same else "none besides the data file"))
if own:
    print("        the game's own files (sceIo, not the save utility): " + "; ".join(own))
print(f"        {data_file}: {os.path.getsize(os.path.join(port_dir, data_file))} bytes (port), "
      f"{os.path.getsize(os.path.join(pp_dir, data_file))} (PPSSPP)")

if not (os.path.exists(port_plain) and os.path.exists(pp_plain)):
    bad("no decrypted contents to compare")
    sys.exit(fails)
p, q = open(port_plain, "rb").read(), open(pp_plain, "rb").read()
if len(p) != len(q):
    bad(f"decrypted lengths differ: {len(p)} and {len(q)}")
diffs = [i for i in range(min(len(p), len(q))) if p[i] != q[i]]
# A word holding an address in the PSP's user RAM on both sides (a pointer the game keeps in its save).
covered, words = set(), []
for i in diffs:
    if i in covered:
        continue
    for k in range(4):
        s = i - k
        if s < 0 or s + 4 > len(p):
            continue
        wp, wq = int.from_bytes(p[s:s + 4], "little"), int.from_bytes(q[s:s + 4], "little")
        if 0x08800000 <= wp < 0x0A000000 and 0x08800000 <= wq < 0x0A000000:
            words.append((s, wp, wq))
            covered.update(range(s, s + 4))
            break
rest = [i for i in diffs if i not in covered]
print(f"        decrypted {len(p)} bytes each; {len(diffs)} differ")
if words:
    deltas = sorted(set(wp - wq for _, wp, wq in words))
    print(f"        {len(words)} words hold guest addresses (user RAM) on both sides, port minus PPSSPP "
          + ", ".join(f"{d:+#x}" for d in deltas) + f": offsets 0x{words[0][0]:x} to 0x{words[-1][0]:x}, e.g. "
          + ", ".join(f"0x{s:x} 0x{wp:08x}/0x{wq:08x}" for s, wp, wq in words[:3]))
if rest:
    ranges = []
    for i in rest:
        if ranges and i <= ranges[-1][1] + 1:
            ranges[-1][1] = i
        else:
            ranges.append([i, i])
    print("        other differences: " + ", ".join(f"0x{s:x}-0x{e:x} ({q[s:e + 1].hex()} PPSSPP, {p[s:e + 1].hex()} port)"
                                                  for s, e in ranges[:12]) + (" ..." if len(ranges) > 12 else ""))
elif not diffs:
    print("        the decrypted contents are identical")
else:
    print("        nothing else differs")
sys.exit(fails)
EOF
  FAILS=$((FAILS + $?))
}
compare profile-born "$OUT/born/game/ms0/PSP/SAVEDATA/$PROFILE" "$REF_PPSSPP/$PROFILE" PROFILE.BIN
compare profile-roundtrip "$OUT/port-roundtrip/$PROFILE" "$REF_PPSSPP/$PROFILE" PROFILE.BIN
compare dls001-born "$OUT/born/game/ms0/PSP/SAVEDATA/$DLS" "$REF_PPSSPP/$DLS" DATA1.BIN
OUTCOME[5]="(c) side by side: $(verdict "both sides verify under the framework's checks; PARAM.SFO fields and the flag byte equal; contents compared above")"
TOTAL=$((TOTAL + FAILS))

echo
for i in 1 2 3 4 5; do echo "${OUTCOME[$i]}"; done
if [ $TOTAL -eq 0 ] && [ $PORT_ONLY -eq 1 ]; then echo "save interchange: the port's side passes; (b) not run"; exit 3; fi
if [ $TOTAL -eq 0 ]; then echo "save interchange: PASS"; exit 0; fi
echo "save interchange: FAIL ($TOTAL checks)"; exit 1
