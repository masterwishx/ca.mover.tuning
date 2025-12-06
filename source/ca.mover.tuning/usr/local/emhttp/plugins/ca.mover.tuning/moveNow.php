#!/usr/bin/php
<?PHP
$vars = @parse_ini_file("/var/local/emhttp/var.ini");
if (version_compare($vars['version'], '7.2.1', '<')) {
    exec("/usr/local/sbin/mover.old start >> /var/log/syslog &", $output, $retval);
} else {
    exec("/usr/local/sbin/mover start >> /var/log/syslog &", $output, $retval);
}
?>