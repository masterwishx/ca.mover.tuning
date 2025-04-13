#!/usr/bin/php
<?PHP
exec("/usr/local/sbin/mover.old start >> /var/log/syslog &", $output, $retval);
?>