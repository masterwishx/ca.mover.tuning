<?PHP
// One file from the log folder for the Log files row on the Mover Tuning tab: shown in the browser, or saved with download=1.
// Only the names age_mover gives its logs and summaries are served, so no other file can be asked for.
$plugin = 'ca.mover.tuning';
$name = (string)($_GET['file'] ?? '');
if (preg_match('/\A(Mover_tuning|Debug_Mover_tuning|Summary)_\d{4}-\d{2}-\d{2}T\d{6}\.(log|txt)\z/', $name) !== 1) {
    http_response_code(400);
    exit;
}
$cfg = @parse_ini_file("/boot/config/plugins/$plugin/$plugin.cfg") ?: [];
// as age_mover: an empty or relative folder is /tmp
$parent = str_starts_with($cfg['loggingFolder'] ?? '', '/') ? $cfg['loggingFolder'] : '/tmp';
$file = rtrim($parent, '/') . "/$plugin/$name";
if (is_file($file) === false) {
    http_response_code(404);
    exit;
}
header('Content-Type: text/plain; charset=utf-8');
header('Content-Length: ' . filesize($file));
header('Content-Disposition: ' . (($_GET['download'] ?? '') === '1' ? 'attachment' : 'inline') . "; filename=\"$name\"");
readfile($file);
?>
