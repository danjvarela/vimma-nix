#!/usr/bin/env bash
# Bump flake.nix to the latest upstream Vimma release.
#
# Re-pins `version` and `hash` from the release's own SHA256SUMS, then prints
# the diff and stops. It never commits, pushes or rebuilds: review the diff,
# build it, then commit yourself.
set -euo pipefail

repo="vimma-browser/vimma"
dir="$(dirname "$(readlink -f "$0")")"
flake="$dir/flake.nix"

release=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest")
tag=$(jq -r .tag_name <<<"$release")
version="${tag#v}"

# Each release is named "Vimma <version> · Firefox <ffversion>"; the Firefox
# base is worth recording, since it is what decides which extensions and web
# features the build actually supports.
firefox=$(jq -r .name <<<"$release" | grep -oP 'Firefox \K[0-9.]+' || echo "unknown")

current=$(grep -oP '^\s*version = "\K[^"]+' "$flake")
if [[ "$version" == "$current" ]]; then
  echo "already on $version (latest)"
  exit 0
fi

echo "$current -> $version (Firefox $firefox)"

tarball="vimma-$version-linux-x86_64.tar.xz"
sums=$(curl -fsSL "https://github.com/$repo/releases/download/$tag/SHA256SUMS")

# The release ships one SHA256SUMS covering every artifact; take the line for
# the linux tarball, the only one this flake fetches.
hex=$(awk -v f="$tarball" '$2 == f { print $1 }' <<<"$sums")
if [[ -z "$hex" ]]; then
  echo "no $tarball in SHA256SUMS for $tag" >&2
  exit 1
fi

sri=$(nix hash convert --hash-algo sha256 --to sri "$hex")

# Three pinned sites: the version line (whose trailing comment names both
# versions), the hex digest kept as a comment so it can be diffed against
# SHA256SUMS by eye, and the SRI hash fetchurl actually checks.
sed -i \
  -e "s|^\([[:space:]]*\)version = \"[^\"]*\";.*$|\1version = \"$version\"; # Vimma $version - Firefox $firefox|" \
  -e "s|^\([[:space:]]*\)# [0-9a-f]\{64\}$|\1# $hex|" \
  -e "s|^\([[:space:]]*\)hash = \"sha256-[^\"]*\";|\1hash = \"$sri\";|" \
  "$flake"

echo
git -C "$dir" --no-pager diff -- flake.nix
echo
echo "review, then: nix build .#vimma && git commit -am \"chore: vimma $version\""
