#!/bin/bash
# Keeps patches/ in step with the changes made in vendor/portablekit. Clones nothing.
#
#   tools/patches.sh check              vendor/portablekit HEAD must equal vendor/PIN, and applying patches/*.patch
#                                       in order to a clean checkout of that commit must reproduce the live vendor
#                                       tree exactly. Prints "ok", or the first differing file and exits 1.
#   tools/patches.sh export NNNN-slug   write patches/NNNN-slug.patch with the vendor changes the series does not
#                                       cover yet (the delta beyond the existing patches). Refuses an NNNN that
#                                       exists or is not above the last one, since the delta applies after all of them.
#
# The clean checkout is a temporary `git worktree` of the pinned commit, removed on exit; the live tree is never
# stashed or reset.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
vendor="$root/vendor/portablekit"
cd "$root"
usage() { echo "usage: tools/patches.sh check | export NNNN-slug" >&2; exit 2; }

mode="${1:-}"
name="${2:-}"
case "$mode" in
check) ;;
export) [[ "$name" =~ ^[0-9]{4}-[a-z0-9][a-z0-9-]*$ ]] || usage ;;
*) usage ;;
esac

[ -d "$vendor/.git" ] || { echo "vendor/portablekit missing (tools/vendor_setup.sh)" >&2; exit 1; }
[ -s vendor/PIN ] || { echo "vendor/PIN missing (tools/vendor_setup.sh)" >&2; exit 1; }
pin=$(tr -d '[:space:]' < vendor/PIN)
head=$(git -C "$vendor" rev-parse HEAD)
[ "$head" = "$pin" ] || { echo "vendor/portablekit HEAD $head is not vendor/PIN $pin" >&2; exit 1; }

shopt -s nullglob
series=(patches/[0-9][0-9][0-9][0-9]-*.patch)

if [ "$mode" = export ]; then
    num=${name%%-*}
    existing=(patches/"$num"-*.patch)
    [ ${#existing[@]} -eq 0 ] || { echo "refusing: ${existing[0]} already uses $num" >&2; exit 1; }
    if [ ${#series[@]} -gt 0 ]; then
        last=$(basename "${series[${#series[@]}-1]}"); last=${last%%-*}
        [ "$((10#$num))" -gt "$((10#$last))" ] || { echo "refusing: $num is not above the last patch, $last" >&2; exit 1; }
    fi
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/pure-patches.XXXXXX")
cleanup() {
    git -C "$vendor" worktree remove --force "$work" >/dev/null 2>&1 || true
    rm -rf "$work"
    git -C "$vendor" worktree prune >/dev/null 2>&1 || true
}
trap cleanup EXIT
git -C "$vendor" worktree add --quiet --detach "$work" "$pin"
for p in "${series[@]}"; do
    git -C "$work" apply "$root/$p" || { echo "does not apply to $pin: $p" >&2; exit 1; }
done

# Paths that differ from the pinned commit in either tree. Anything outside both lists is the pinned file in both.
changed() { git -C "$1" -c core.quotepath=false status --porcelain --untracked-files=all --no-renames | cut -c4-; }
paths=$( { changed "$vendor"; changed "$work"; } | LC_ALL=C sort -u)

# Same file in both trees: present in both or neither, same bytes, same executable bit.
same() {
    local a="$vendor/$1" b="$work/$1"
    [ -e "$a" ] || [ -L "$a" ] || { [ ! -e "$b" ] && [ ! -L "$b" ]; return; }
    [ -e "$b" ] || [ -L "$b" ] || return 1
    cmp -s "$a" "$b" || return 1
    [ -x "$a" ] && [ -x "$b" ] && return 0
    [ ! -x "$a" ] && [ ! -x "$b" ]
}

case "$mode" in
check)
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        same "$f" || { echo "differs: vendor/portablekit/$f"; exit 1; }
    done <<< "$paths"
    echo "ok: ${#series[@]} patch(es) reproduce vendor/portablekit at ${pin:0:7}"
    ;;
export)
    # Stage what the series produced, copy the live tree's version of every differing path over it, and diff:
    # the result holds only what is new.
    git -C "$work" add --all
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        same "$f" && continue
        if [ -e "$vendor/$f" ] || [ -L "$vendor/$f" ]; then
            mkdir -p "$(dirname "$work/$f")"
            cp -pP "$vendor/$f" "$work/$f"
            git -C "$work" add --intent-to-add -- "$f"
        else
            rm -f "$work/$f"
        fi
    done <<< "$paths"
    out="patches/$name.patch"
    git -C "$work" -c core.quotepath=false -c diff.noprefix=false -c diff.mnemonicPrefix=false \
        diff --no-color --no-ext-diff --binary > "$out"
    if [ ! -s "$out" ]; then
        rm -f "$out"
        echo "nothing to export: the series already reproduces vendor/portablekit"
        exit 0
    fi
    echo "wrote $out:"
    grep '^diff --git' "$out" | sed 's|^diff --git a/\(.*\) b/.*|  \1|'
    echo "now add its row to patches/README.md (| $name | Kind | Why |) and commit patches/, never vendor/"
    ;;
esac
