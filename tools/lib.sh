# What the bash checks share (task 094), each written once. Sourced, not run, after the check's
# `cd "$(dirname "$0")/.."` (the checkout's root) and `. tools/env.sh`:
#   need_game                 the build/game guard: sets EXE to the binary purelib.port names (build/arm64 on macOS,
#                             build/win-x64 on Windows; forward slashes) and exits 2 when it, game/EBOOT.ELF or the
#                             image game/disc.iso names is missing.
#   wait_game TOOL [SECONDS]  the one-game wait (task 034: one game at a time): while another PureNative runs, waits
#                             (purelib.port.wait_until, saying so as TOOL) at most SECONDS (default 600; 0 gives up
#                             at once). Returns 0 when no other game runs, 2 when it gave up.
#   window_shell              prints the default window shell: vulkan under MINGW/MSYS/CYGWIN (the rig), metal
#                             elsewhere.
#   pick_backend TOOL SHELLS [WHY]  the shell/backend arguments: SHELL_NAME must be one of SHELLS (a space-separated
#                             list), BACKEND defaults to the shell's own (vulkan under the Vulkan shell, metal
#                             otherwise) and must be metal or vulkan; otherwise TOOL's usage message (WHY appended to
#                             the shell's) and exit 2.
#   fresh_stick DIR           makes DIR a game directory on an empty memory stick (purelib.port.fresh_stick: EBOOT.ELF
#                             and disc.iso linked to game/'s, ms0/PSP/SAVEDATA emptied): symlinks on macOS, hard links
#                             on Windows, where Git Bash's `ln -s` copies the 253 MB image (task 054). Exits 2 when
#                             game/ lacks a file.

need_game() {
  EXE=$(python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port; print(port.EXE.as_posix())')
  [ -x "$EXE" ] || { echo "$EXE missing: tools/build.sh profile"; exit 2; }
  [ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
  [ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }
}

wait_game() {
  python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port
tool, limit = sys.argv[1], float(sys.argv[2])
sys.exit(0 if port.wait_until(port.other_games, port.REFUSED, lambda m: print(f"{tool}: {m}", flush=True),
                              limit=limit) else 2)' "$1" "${2:-600}"
}

window_shell() {
  case $(uname -s) in
    MINGW*|MSYS*|CYGWIN*) echo vulkan ;;
    *) echo metal ;;
  esac
}

pick_backend() {
  local tool=$1 shells=$2 why=${3:-} list
  case " $shells " in
    *" $SHELL_NAME "*) ;;
    *) list=$(echo $shells | awk '{ s = $1; for (i = 2; i <= NF; i++) s = s (i == NF ? " or " : ", ") $i; print s }')
       echo "$tool: --shell is $list${why:+ ($why)}, not $SHELL_NAME"
       exit 2 ;;
  esac
  if [ "$SHELL_NAME" = vulkan ]; then BACKEND=${BACKEND:-vulkan}; else BACKEND=${BACKEND:-metal}; fi
  case $BACKEND in metal|vulkan) ;; *) echo "$tool: --backend is metal or vulkan, not $BACKEND"; exit 2 ;; esac
}

fresh_stick() {
  python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port
try:
    port.fresh_stick(sys.argv[1])
except FileNotFoundError as e:
    sys.exit(str(e))' "$1" || exit 2
}
