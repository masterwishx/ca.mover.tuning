<?PHP
// Progress of the running move for MoverTuningProgress.page, read from the status file age_mover and Unraid 7.4's mover write.
// A status file whose MoverPid is not the live pid in /var/run/mover.pid is left over from another run: null.
header('Content-Type: application/json');
$pid = trim((string)@file_get_contents('/var/run/mover.pid'));
$status = ctype_digit($pid) === true && is_dir("/proc/$pid") === true ? @parse_ini_file('/usr/local/emhttp/state/mover.ini') : false;
if (is_array($status) === false || (string)($status['MoverPid'] ?? '') !== $pid) {
    echo 'null';
    exit;
}
echo json_encode([
    'file' => (string)($status['File'] ?? ''),
    'action' => (string)($status['Action'] ?? ''),
    'total' => (int)($status['TotalSize'] ?? 0),
    'remain' => (int)($status['RemainSize'] ?? 0),
    'speed' => (int)($status['Throughput'] ?? 0),
    'eta' => (int)($status['ETA'] ?? 0),
], JSON_INVALID_UTF8_SUBSTITUTE);
?>
