# Patches against the vendored framework

Applied in numeric order by `tools/vendor_setup.sh` (`git apply` inside `vendor/yakumo`). `tools/patches.sh check`
applies the series to a clean checkout of the pinned commit and compares it with the vendor tree;
`tools/patches.sh export NNNN-slug` writes a new patch from the vendor tree's uncommitted changes.

| Patch | Kind | Why |
|---|---|---|

Kinds: Layout constant, Bug, Missing feature, Tooling, Speed. Patches that could go upstream are marked in the Why column.
| 0001-embed-nids-verbatim | Bug | `portablekit_add_game` passes `-DINPUT=a.csv|b.csv` to the shell unquoted when a profile ships `config/nids.csv`; the `|` becomes a pipe. Adds `VERBATIM`. Upstream candidate |
