#!/bin/bash
DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
tmpdir=$(mktemp -d)
plugin=$(basename "${DIR}")
archive="$(dirname "$(dirname "${DIR}")")/archive"
version=$(date +"%Y.%m.%d.%H%M")$1
config_file=../../plugins/ca.mover.tuning.plg

find . -type f ! -iname "pkg_build.sh" -exec cp --parents "{}" "$tmpdir"/ \;
find "$tmpdir" -type f | sed s,^"$tmpdir/",, | tar -czf "${archive}/${plugin}-${version}-x86_64-1.txz" --no-recursion --owner=0 --group=0 -C "$tmpdir/" -T -
rm -rf "$tmpdir"

package_md5=$(md5sum "${archive}/${plugin}-${version}-x86_64-1.txz" | awk '{print $1}')

echo "Version: $version"
echo "MD5: $package_md5"
echo ""
echo "Updating ca.mover.plugin.plg"
cd "$DIR" || exit
sed -i "s/<!ENTITY md5.*/<!ENTITY md5       \"$package_md5\">/" "$config_file"
sed -i "s/<!ENTITY version.*/<!ENTITY version   \"$version\">/" "$config_file"