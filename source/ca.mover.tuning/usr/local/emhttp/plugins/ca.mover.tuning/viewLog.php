<?PHP
// One file from the log folder for the Log files row on the Mover Tuning tab: shown in the browser, or saved with download=1.
// Only a name from the list of logs is served, so no other file can be asked for.
require_once '/usr/local/emhttp/plugins/ca.mover.tuning/logFiles.php';
$name = (string)($_GET['file'] ?? '');
$cfg = @parse_ini_file('/boot/config/plugins/ca.mover.tuning/ca.mover.tuning.cfg');
$file = moverLogFiles(is_array($cfg) ? $cfg : [])[$name] ?? '';
if ($file === '') {
    http_response_code(404);
    exit;
}
header('Content-Type: text/plain; charset=utf-8');
header('Content-Length: ' . filesize($file));
header('Content-Disposition: ' . (($_GET['download'] ?? '') === '1' ? 'attachment' : 'inline') . "; filename=\"$name\"");
readfile($file);
?>
