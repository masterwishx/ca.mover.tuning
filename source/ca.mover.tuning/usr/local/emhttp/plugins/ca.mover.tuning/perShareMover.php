#!/usr/bin/php
<?PHP
/* Copyright 2005-2023, Lime Technology
 * Copyright 2012-2023, Bergware International.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version 2,
 * as published by the Free Software Foundation.
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 */
?>
<?
#---------------------------------------------------------------------------------------------------------------------
#This section was adapted from "Wrapper.php" and includes an adapted "parse_plugin_cfg()" function.
$docroot = $docroot ?? $_SERVER['DOCUMENT_ROOT'] ?: '/usr/local/emhttp';
function parse_share_cfg($plugin, $shareName, $sections = false, $scanner = INI_SCANNER_NORMAL)
{
    global $docroot;
    $ram = "$docroot/plugins/$plugin/default.cfg";
    $rom = "/boot/config/plugins/$plugin/shareOverrideConfig/$shareName.cfg";
    $cfg = file_exists($ram) ? parse_ini_file($ram, $sections, $scanner) : [];
    return file_exists($rom) ? array_replace_recursive($cfg, parse_ini_file($rom, $sections, $scanner)) : $cfg;
}
#---------------------------------------------------------------------------------------------------------------------
?>