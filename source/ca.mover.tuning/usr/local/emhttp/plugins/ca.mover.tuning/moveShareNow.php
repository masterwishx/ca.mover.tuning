#!/usr/bin/php
<?PHP
$shareName = $_POST['Share'] ?? '';
$cfgs = glob('/boot/config/shares/*.cfg');
$shares = $cfgs === false ? [] : array_map(fn($cfg) => basename($cfg, '.cfg'), $cfgs);
if (in_array($shareName, $shares, true) === false) {
    exit;
}
// Constant command line; the name reaches share_mover through the environment, so the shell never parses it
putenv("MOVER_SHARE=$shareName");
exec('/usr/local/emhttp/plugins/ca.mover.tuning/share_mover "$MOVER_SHARE" >> /var/log/syslog &', $output, $retval);
?>
