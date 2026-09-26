<?PHP
// No #!/usr/bin/php line here: php-fpm would send it as body text before this runs, and the status could not be set
exec("/usr/local/emhttp/plugins/ca.mover.tuning/age_mover reset >> /var/log/syslog", $output, $retval);
if ($retval !== 0) {
	http_response_code(500);
}
?>