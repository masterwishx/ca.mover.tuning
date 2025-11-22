#!/usr/bin/php
<?
exec("/usr/local/sbin/mover.old start >> /var/log/syslog &", $output, $retval);
?>
