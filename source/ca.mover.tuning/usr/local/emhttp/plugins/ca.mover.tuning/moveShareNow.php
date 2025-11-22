#!/usr/bin/php
<?
$shareName = $_GET['Share'];
//exec("echo {$shareName} >> /var/log/syslog");
exec("/usr/local/emhttp/plugins/ca.mover.tuning/share_mover {$shareName} >> /var/log/syslog &", $output, $retval);
?>
