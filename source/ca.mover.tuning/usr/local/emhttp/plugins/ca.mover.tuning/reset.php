#!/usr/bin/php
<?PHP
exec("/usr/local/emhttp/plugins/ca.mover.tuning/age_mover reset >> /var/log/syslog &", $output, $retval);
?>