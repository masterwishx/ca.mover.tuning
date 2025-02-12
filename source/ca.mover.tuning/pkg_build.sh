#!/bin/bash
DIR="$(dirname "$(readlink -f ${BASH_SOURCE[0]})")"
tmpdir=/tmp/tmp.$(( $RANDOM * 19318203981230 + 40 ))
plugin=$(basename ${DIR})
archive="$(dirname $(dirname ${DIR}))/archive"
version=$(date +"%Y.%m.%d.%H%M")$1
config_file=/mnt/user/appdata/AutoSlackPack/in/ca.mover.tuning//plugins/ca.mover.tuning.plg

mkdir -p $tmpdir

cp --parents -f $(find . -type f ! \( -iname "pkg_build.sh" -o -iname "sftp-config.json"  \) ) $tmpdir/
cd $tmpdir
makepkg -l y -c y ${archive}/${plugin}-${version}-x86_64-1.txz
rm -rf $tmpdir
package_md5=$(md5sum ${archive}/${plugin}-${version}-x86_64-1.txz | awk '{print $1}')
echo "Version: $version"
echo "MD5: $package_md5"
echo ""
echo "Updating ca.mover.plugin.plg"
sed -i "s/<!ENTITY md5.*/<!ENTITY md5       \"$package_md5\">/" "$config_file"
sed -i "s/<!ENTITY version.*/<!ENTITY version   \"$version\">/" "$config_file"