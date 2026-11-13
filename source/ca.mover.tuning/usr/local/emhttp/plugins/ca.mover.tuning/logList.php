<?PHP
// The names for the Log files row on the Mover Tuning tab, newest first: the files viewLog.php serves.
require_once '/usr/local/emhttp/plugins/ca.mover.tuning/logFiles.php';
$cfg = @parse_ini_file('/boot/config/plugins/ca.mover.tuning/ca.mover.tuning.cfg');
header('Content-Type: application/json');
echo json_encode(array_keys(moverLogFiles(is_array($cfg) === true ? $cfg : [])));
?>
