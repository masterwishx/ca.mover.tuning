#!/bin/bash

# Get the directory of the script
DIR="$(dirname "$(readlink -f ${BASH_SOURCE[0]})")"

# Set the temporary directory and plugin name
tmpdir=/tmp/tmp.$(( RANDOM * 19318203981230 + 40 ))
plugin=$(basename "${DIR}")
archive="$(dirname "$(dirname "${DIR}")")/archive"
# $2 is argument addition to date (a,b,c)
version=$(date +"%Y.%m.%d")$2
# $1 Path to the plugin directory
config_file="$1/$plugin/plugins/$plugin.plg"
readme_file="$1/$plugin/README.md"
default_config_file="$1/$plugin/source/$plugin/usr/local/emhttp/plugins/$plugin/default.cfg"
# Create the temporary directory and copy files
mkdir -p $tmpdir

# Get the content from .update file
update_content="$(dirname $(dirname "$DIR"))/.updates.txt"

# Step 0: Change to current version in $default_config_file
sed -i "s/version=.*/version=\"$version\"/" "$default_config_file"

cp --parents -f $(find . -type f ! \( -iname "pkg_build.sh" -o -iname "sftp-config.json"  \) ) $tmpdir/

cd $tmpdir

# Build the package using makepkg
makepkg -l y -c y ${archive}/${plugin}-${version}-x86_64-1.txz

# Calculate the MD5 hash of the package
package_md5=$(md5sum ${archive}/${plugin}-${version}-x86_64-1.txz | awk '{print $1}')

echo "Version: $version"
echo "MD5: $package_md5"
echo ""
echo "Update Content: $update_content"
echo ""
echo "Updating $plugin.plg"
echo "Updating README.md"
echo "Updating default.cfg"

sed -i "s/<!ENTITY md5.*/<!ENTITY md5       \"$package_md5\">/" "$config_file"
sed -i "s/<!ENTITY version.*/<!ENTITY version   \"$version\">/" "$config_file"

# Define variables for your files and version
tmp_config_file="$tmpdir/tmp_config_file.txt"
tmp_readme_file="$tmpdir/tmp_readme_file.txt"

# Modify the config file (*.plg) with changelog
# Step 1: Cut content after ### from $config_file to $tmp_config_file
sed -n '/###*/,$p' "$config_file" > "$tmp_config_file"
# Step 2: Dlete evrything after ### in $config_file
sed -i '/###*/,$d' "$config_file"
# Step 3: Add version to $config_file
sed -i '$a\###'${version}'' "$config_file"
# Step 4: Add content from $update_content to $config_file
cat "$update_content" >> "$config_file"; echo -e "\n" >> "$config_file"
# Step 5: Add content from $tmp_config_file to $config_file
cat "$tmp_config_file" >> "$config_file"

# Modify the readme file with changelog
# Step 1: Cut content after ## Changelog from $readme_file to $tmp_readme_file
sed -n '/- 20*/,$p' "$readme_file" > "$tmp_readme_file"
# Step 2: Dlete evrything after ## Changelog in $readme_file
sed -i '/- 20*/,$d' "$readme_file"
# Step 3: Add version to $readme_file
sed -i '$a\- '${version}'' "$readme_file"
# Step 4: Add content from $update_content to $readme_file
cat "$update_content" | sed -e 's/^/    /' >> "$readme_file"; echo -e "\n" >> "$readme_file"
# Step 5: Add content from $tmp_readme_file to $readme_file
cat "$tmp_readme_file" >> "$readme_file"

# Clean up the temporary directory
rm -rf $tmpdir
