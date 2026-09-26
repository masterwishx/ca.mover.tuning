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
/** The share page's settings: each key of default.cfg, empty (Use global) unless the share file saved it. */
function parse_share_cfg($plugin, $shareName, $sections = false, $scanner = INI_SCANNER_NORMAL)
{
    global $docroot;
    $ram = "$docroot/plugins/$plugin/default.cfg";
    $rom = "/boot/config/plugins/$plugin/shareOverrideConfig/$shareName.cfg";
    $cfg = file_exists($ram) ? parse_ini_file($ram, $sections, $scanner) : [];
    // a setting the share file has not saved is Use global (empty), as age_mover reads it, not the shipped default
    $cfg = is_array($cfg) === true ? array_fill_keys(array_keys($cfg), '') : [];
    $share = file_exists($rom) === true ? parse_ini_file($rom, $sections, $scanner) : [];
    return $share === false ? $cfg : array_replace_recursive($cfg, $share);
}
#---------------------------------------------------------------------------------------------------------------------
?>