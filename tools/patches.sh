#!/bin/bash
# Keeps patches/ in step with the changes made in vendor/portablekit. Clones nothing.
#
#   tools/patches.sh check              vendor/portablekit HEAD must equal vendor/PIN, and applying patches/*.patch
#                                       in order to a clean checkout of that commit must reproduce the live vendor
#                                       tree exactly. Prints "ok", or the first differing file and exits 1.
#   tools/patches.sh export NNNN-slug   write patches/NNNN-slug.patch with the vendor changes the series does not
#                                       cover yet (the delta beyond the existing patches). Refuses an NNNN that
#                                       exists or is not above the last one, since the delta applies after all of them.
#   tools/patches.sh open [DIR]         materialise the series to edit a patch in the middle of it: a git worktree of
#                                       vendor/PIN at DIR (default out/patch-series) on the branch `patch-series`,
#                                       one commit a patch in order, each commit's subject the patch's name
#                                       (NNNN-slug). Refused unless `check` passes, so the vendor tree holds nothing
#                                       the series does not.
#   tools/patches.sh close [DIR]        write each commit of the branch back to patches/<subject>.patch, delete the
#                                       patches/ file of a patch whose commit is gone (a dropped patch leaves its
#                                       number unused), bring vendor/portablekit to the branch's last commit (only
#                                       the files whose bytes differ are written, so an untouched file keeps its time
#                                       stamp and nothing rebuilds for it), run `check`, then remove the worktree and
#                                       the branch. Refused while the worktree has uncommitted changes or a rebase
#                                       in progress, or when the branch does not start at vendor/PIN.
#
# Editing patch 0004 in the middle of the series (inside DIR, any git commands; no interactive editor is needed):
#   tools/patches.sh open
#   cd out/patch-series && <edit> && git commit -a --fixup="$(git log -1 --format=%H --grep=^0004-)"
#   GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash "$(cat ../../vendor/PIN)"   # into 0004's commit
#   cd ../.. && tools/patches.sh close
# A conflict in a later patch is resolved as in any rebase. Dropping a patch: `git rebase --onto C^ C` (C its commit). A new patch at the end: a commit whose subject is its
# name; its row in patches/README.md is still written by hand. Rewording a subject renames the patch.
#
# The clean checkout of check and export is a temporary `git worktree` of the pinned commit, removed on exit; the live
# tree is never stashed or reset.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
vendor="$root/vendor/portablekit"
cd "$root"
usage() { echo "usage: tools/patches.sh check | export NNNN-slug | open [DIR] | close [DIR]" >&2; exit 2; }

mode="${1:-}"
name="${2:-}"
case "$mode" in
check) ;;
export) [[ "$name" =~ ^[0-9]{4}-[a-z0-9][a-z0-9-]*$ ]] || usage ;;
open|close) [ $# -le 2 ] || usage ;;
*) usage ;;
esac

[ -d "$vendor/.git" ] || { echo "vendor/portablekit missing (tools/vendor_setup.sh)" >&2; exit 1; }
[ -s vendor/PIN ] || { echo "vendor/PIN missing (tools/vendor_setup.sh)" >&2; exit 1; }
pin=$(tr -d '[:space:]' < vendor/PIN)
head=$(git -C "$vendor" rev-parse HEAD)
[ "$head" = "$pin" ] || { echo "vendor/portablekit HEAD $head is not vendor/PIN $pin" >&2; exit 1; }

shopt -s nullglob
series=(patches/[0-9][0-9][0-9][0-9]-*.patch)

# Paths that differ from the pinned commit in a tree. Anything outside the lists of two trees is the pinned file in both.
changed() { git -C "$1" -c core.quotepath=false status --porcelain --untracked-files=all --no-renames | cut -c4-; }

# Same file under two roots: present in both or neither, same bytes, same executable bit.
same_in() {
    local a="$1/$3" b="$2/$3"
    [ -e "$a" ] || [ -L "$a" ] || { [ ! -e "$b" ] && [ ! -L "$b" ]; return; }
    [ -e "$b" ] || [ -L "$b" ] || return 1
    cmp -s "$a" "$b" || return 1
    [ -x "$a" ] && [ -x "$b" ] && return 0
    [ ! -x "$a" ] && [ ! -x "$b" ]
}

branch=patch-series
if [ "$mode" = open ] || [ "$mode" = close ]; then
    dir="${name:-out/patch-series}"
    case "$dir" in /*) ;; *) dir="$root/$dir" ;; esac
fi

if [ "$mode" = open ]; then
    [ ! -e "$dir" ] || { echo "refusing: $dir exists (tools/patches.sh close it, or remove it)" >&2; exit 1; }
    ! git -C "$vendor" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null ||
        { echo "refusing: vendor/portablekit has a branch $branch already (git -C vendor/portablekit branch -D $branch)" >&2; exit 1; }
    "$root/tools/patches.sh" check >/dev/null || { echo "refusing: tools/patches.sh check fails; export or discard the vendor change first" >&2; exit 1; }
    mkdir -p "$(dirname "$dir")"
    git -C "$vendor" worktree add --quiet -b "$branch" "$dir" "$pin"
    for p in "${series[@]}"; do
        n=$(basename "$p" .patch)
        # Applied to the working tree and then staged, not `apply --index`: on Windows (core.autocrlf true) the
        # worktree holds CRLF where the index holds LF and --index refuses every patch (task 501); `add` normalises.
        git -C "$dir" apply "$root/$p" || { echo "does not apply: $p (the worktree is left at $dir)" >&2; exit 1; }
        git -C "$dir" add -A
        git -C "$dir" -c user.name=patches.sh -c user.email=patches.sh@localhost commit --quiet --no-verify -m "$n"
    done
    echo "opened $dir on branch $branch: ${#series[@]} commit(s) on ${pin:0:7}"
    echo "edit, commit with --fixup, squash: GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash $pin"
    echo "then: tools/patches.sh close${name:+ $name}"
    exit 0
fi

if [ "$mode" = close ]; then
    [ -d "$dir" ] || { echo "no series worktree at $dir (tools/patches.sh open)" >&2; exit 1; }
    [ "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" = "$branch" ] || { echo "refusing: $dir is not on branch $branch" >&2; exit 1; }
    for d in rebase-merge rebase-apply; do
        [ ! -e "$(git -C "$dir" rev-parse --path-format=absolute --git-path "$d")" ] ||
            { echo "refusing: a rebase is in progress in $dir" >&2; exit 1; }
    done
    [ -z "$(git -C "$dir" status --porcelain --untracked-files=all)" ] ||
        { echo "refusing: $dir has uncommitted changes" >&2; exit 1; }
    git -C "$dir" merge-base --is-ancestor "$pin" HEAD || { echo "refusing: $branch does not start at vendor/PIN ${pin:0:7}" >&2; exit 1; }
    [ -z "$(git -C "$dir" rev-list --merges "$pin..HEAD")" ] || { echo "refusing: $branch has merge commits" >&2; exit 1; }
    commits=($(git -C "$dir" rev-list --reverse "$pin..HEAD"))
    # Every subject a patch name, numbers rising, no commit empty.
    names=()
    last=0
    for c in "${commits[@]}"; do
        s=$(git -C "$dir" log -1 --format=%s "$c")
        [[ "$s" =~ ^[0-9]{4}-[a-z0-9][a-z0-9-]*$ ]] || { echo "refusing: commit ${c:0:7} '$s' is not named NNNN-slug" >&2; exit 1; }
        num=$((10#${s%%-*}))
        [ "$num" -gt "$last" ] || { echo "refusing: $s does not come after patch $last" >&2; exit 1; }
        last=$num
        [ -n "$(git -C "$dir" diff --name-only "$c^" "$c")" ] || { echo "refusing: $s is empty; drop its commit" >&2; exit 1; }
        names+=("$s")
    done
    # The patches, as export writes them.
    for i in "${!commits[@]}"; do
        c=${commits[$i]}
        out="patches/${names[$i]}.patch"
        git -C "$dir" -c core.quotepath=false -c diff.noprefix=false -c diff.mnemonicPrefix=false \
            diff --no-color --no-ext-diff --no-renames --binary "$c^" "$c" > "$out"
    done
    for p in "${series[@]}"; do
        n=$(basename "$p" .patch)
        keep=
        for s in "${names[@]}"; do [ "$s" = "$n" ] && keep=1; done
        [ -n "$keep" ] || { rm -f "$p"; echo "removed $p"; }
    done
    # vendor/portablekit to the branch's tree, a file only where its bytes or executable bit differ.
    paths=$( { git -C "$dir" -c core.quotepath=false diff --name-only --no-renames "$pin" HEAD; changed "$vendor"; } | LC_ALL=C sort -u)
    written=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        same_in "$vendor" "$dir" "$f" && continue
        rm -f "$vendor/$f"
        if [ -e "$dir/$f" ] || [ -L "$dir/$f" ]; then
            mkdir -p "$(dirname "$vendor/$f")"
            cp -P "$dir/$f" "$vendor/$f"
        else
            rmdir -p "$(dirname "$vendor/$f")" 2>/dev/null || true
        fi
        echo "  vendor/portablekit/$f"
        written=$((written + 1))
    done <<< "$paths"
    echo "wrote ${#commits[@]} patch(es); $written vendor file(s) changed"
    "$root/tools/patches.sh" check
    git -C "$vendor" worktree remove "$dir"
    git -C "$vendor" branch -q -D "$branch"
    echo "closed $dir; commit patches/ (and its README rows), never vendor/"
    exit 0
fi

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

paths=$( { changed "$vendor"; changed "$work"; } | LC_ALL=C sort -u)
same() { same_in "$vendor" "$work" "$1"; }

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
