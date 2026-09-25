#!/bin/bash
set -euo pipefail

# Usage: pkg_build.sh --version YYYY.MM.DD[a] [--out DIR]
# Writes <plugin>-<version>-x86_64-1.txz to DIR (default: dist/ at the repo root) and stamps its version and md5 into the .plg.
DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
plugin=$(basename "${DIR}")
root="$(dirname "$(dirname "${DIR}")")"
config_file="$root/plugins/$plugin.plg"
version=""
out="$root/dist"
while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done
# the release workflow picks the version; a test build passes its own (.github/workflows/pr-build.yml)
[[ "$version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}[0-9a-z.]*$ ]] || { echo "--version YYYY.MM.DD[suffix] is required" >&2; exit 1; }

mkdir -p "$out"
out=$(cd "$out" && pwd)
package="$out/${plugin}-${version}-x86_64-1.txz"
tmpdir=$(mktemp -d)
trap 'rm -rf -- "$tmpdir"' EXIT

cd "$DIR"
find . -type f ! \( -iname "pkg_build.sh" -o -iname "sftp-config.json" \) -exec cp --parents -f -t "$tmpdir/" {} +
# only the packaged copy carries the version, so master and beta never differ on it
sed -i "s/^version=.*/version=\"$version\"/" "$tmpdir/usr/local/emhttp/plugins/$plugin/default.cfg"

cd "$tmpdir"

# Same layout as `makepkg -l y -c y` (root-owned, 755 dirs), without needing Slackware
find . -type d -exec chmod 755 {} +
find ./ | LC_COLLATE=C sort | sed '2,$s,^\./,,' | tar --no-recursion --owner=0 --group=0 -T - -cJf "$package"

package_md5=$(md5sum "$package" | awk '{print $1}')

sed -i "s/<!ENTITY md5.*/<!ENTITY md5       \"$package_md5\">/" "$config_file"
sed -i "s/<!ENTITY version.*/<!ENTITY version   \"$version\">/" "$config_file"

echo "Version: $version"
echo "MD5: $package_md5"
echo "Package: $package"
