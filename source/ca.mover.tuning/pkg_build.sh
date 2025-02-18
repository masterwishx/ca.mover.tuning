#!/bin/bash

# Get the directory of the script
DIR="$(dirname "$(readlink -f ${BASH_SOURCE[0]})")"

# Set the temporary directory and plugin name
tmpdir=/tmp/tmp.$(( $RANDOM * 19318203981230 + 40 ))
plugin=$(basename ${DIR})
archive="$(dirname $(dirname ${DIR}))/archive"
version=$(date +"%Y.%m.%d.%H%M")$1
config_file=/mnt/user/appdata/AutoSlackPack/in/ca.mover.tuning//plugins/ca.mover.tuning.plg
readme_file="/mnt/user/appdata/AutoSlackPack/in/ca.mover.tuning//README.md"

# Create the temporary directory and copy files
mkdir -p $tmpdir

# Get the content from .update file
update_content="$(dirname $(dirname "$DIR"))/.updates.txt"
update_content=$(cat "$update_content")

cp --parents -f $(find . -type f ! \( -iname "pkg_build.sh" -o -iname "sftp-config.json"  \) ) $tmpdir/
cd $tmpdir

# Build the package using makepkg
makepkg -l y -c y ${archive}/${plugin}-${version}-x86_64-1.txz

# Clean up the temporary directory
rm -rf $tmpdir

# Calculate the MD5 hash of the package
package_md5=$(md5sum ${archive}/${plugin}-${version}-x86_64-1.txz | awk '{print $1}')

echo "Version: $version"
echo "MD5: $package_md5"
echo ""
echo "Update Content: $update_content"
echo ""
echo "Updating ca.mover.plugin.plg"
echo "Updating README.md"

sed -i "s/<!ENTITY md5.*/<!ENTITY md5       \"$package_md5\">/" "$config_file"
sed -i "s/<!ENTITY version.*/<!ENTITY version   \"$version\">/" "$config_file"

# Modify the config file with changelog
#sed -i "/<CHANGES>/a\### $version\n$update_content\n" "$config_file"
#sed -i "s/<CHANGES>/<CHANGES>\\n### $version\\\\n\"$update_content\"\\n/" "$config_file"
#sed -i "s/<CHANGES>/<CHANGES>### $version \"$update_content\"/" "$config_file"

# Modify the config file with changelog
# sed -i "/<CHANGES>/a\\
# ### $version\n\
# $update_content\
# " "$config_file"

#sed "/<CHANGES>/a\n### $version\n$update_content\n" "$config_file"

#sed  '/\[option\]/a Hello World' input

# Modify the readme file with changelog
#sed -i "/## Changelog/a\n$update_content\n" "$readme_file"




# #!/bin/bash

# # Get the directory of the script
# DIR="$(dirname "$(readlink -f ${BASH_SOURCE[0]})")"

# # Create a temporary directory using mktemp for better security
# tmpdir=$(mktemp -d -p /tmp)
# plugin=$(basename "$DIR")
# archive="$(dirname $(dirname "$DIR"))/archive"
# version=$(date +"%Y.%m.%d.%H%M")$1
# config_file="/mnt/user/appdata/AutoSlackPack/in/ca.mover.tuning//plugins/ca.mover.tuning.plg"
# readme_file="/mnt/user/appdata/AutoSlackPack/in/ca.mover.tuning//README.md"

# # Create the temporary directory
# mkdir -p "$tmpdir"

# # Get the content from .update file
# update_content="$(dirname $(dirname "$DIR"))/.updates.txt"
# update_content=$(cat "$update_content")

# # Copy files to the temporary directory, excluding specific files
# #cp --parents -f "$(find . -type f ! \( -iname "pkg_build.sh" \))" "$tmpdir/"
# #cp --parents -f "$(find . -type f ! \( -iname "pkg_build.sh" \))" "$tmpdir/"
# #find . -type f ! \( -iname "pkg_build.sh" \) -exec sed -i 's/\r$//' {} +
# #cp --parents -f "$(find . -type f ! \( -iname "pkg_build.sh" -o -iname "sftp-config.json" \)" $tmpdir/
# #cp --parents -f "$(find . -type f ! \( -iname "pkg_build.sh" -o -iname "sftp-config.json" \))" $tmpdir/

# # Change to the temporary directory
# cd "$tmpdir"

# # Build the package using makepkg
# #makepkg -l y -c y "${archive}/${plugin}-${version}-x86_64-1.txz"

# # Calculate the MD5 checksum of the built package
# #package_md5=$(md5sum "${archive}/${plugin}-${version}-x86_64-1.txz" | awk '{print $1}')

# # Output version and MD5 information
# echo "Version: $version"
# echo "MD5: $package_md5"

# # Update the configuration file
# #sed -i "s/<!ENTITY md5.*/<!ENTITY md5 \"$package_md5\">/" "$config_file"
# sed -i "s/<!ENTITY version.*/<!ENTITY version \"$version\">/" "$config_file"

# # Modify the config file with changelog
# sed -i "/<CHANGES>/a\### $version\n$update_content\n" "$config_file"

# # Modify the readme file with changelog
# #sed -i "/## Changelog/a\n$update_content\n" "$readme_file"

# rm -rf "$tmpdir"