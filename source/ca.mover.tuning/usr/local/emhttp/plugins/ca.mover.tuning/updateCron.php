#!/usr/bin/php
<?
if ( $_POST['cronEnabled'] == "yes" ) {
	$cronFile = "# Generated schedule for forced move\n".trim($_POST['cron'])." /usr/local/sbin/mover.old start 2>/dev/null\n\n";
	file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.cron",$cronFile);
} else {
	@unlink("/boot/config/plugins/ca.mover.tuning/mover.cron");
}
exec("update_cron");
?>
