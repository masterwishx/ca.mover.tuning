#!/usr/bin/php
<?PHP
if ($_POST['cronEnabled'] == "yes") {
	$cronFile = "# Generated schedule for forced move\n" . trim($_POST['cron']) . " /usr/local/sbin/mover.old start |& logger -t move\n\n";	
	file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.cron", $cronFile);
} else {
	@unlink("/boot/config/plugins/ca.mover.tuning/mover.cron");
}
exec("update_cron");
?>