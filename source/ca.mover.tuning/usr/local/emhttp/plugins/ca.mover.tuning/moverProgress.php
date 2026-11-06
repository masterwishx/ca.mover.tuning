<?PHP
// The running move for MoverTuningProgress.page, null when none: whether it moves files and is paused (age_mover's
// mover.moving names its pid while files move), and its progress from the status file age_mover and Unraid 7.4's mover write.
// A status file whose MoverPid is not the live pid in /var/run/mover.pid is left over from another run: no progress.
header('Content-Type: application/json');
$pid = trim((string)@file_get_contents('/var/run/mover.pid'));
if (ctype_digit($pid) === false || is_dir("/proc/$pid") === false) {
    echo 'null';
    exit;
}
// a soft stop always wins over a pause, as age_mover's pauseWindow has it
$moving = strtok((string)@file_get_contents('/var/run/mover.moving'), ' ') === $pid && file_exists('/var/run/moversoft.stop') === false;
$status = @parse_ini_file('/usr/local/emhttp/state/mover.ini');
$progress = null;
if (is_array($status) === true && (string)($status['MoverPid'] ?? '') === $pid) {
    $progress = [
        'file' => (string)($status['File'] ?? ''),
        'action' => (string)($status['Action'] ?? ''),
        'total' => (int)($status['TotalSize'] ?? 0),
        'remain' => (int)($status['RemainSize'] ?? 0),
        'speed' => (int)($status['Throughput'] ?? 0),
        'eta' => (int)($status['ETA'] ?? 0),
    ];
}
echo json_encode([
    'moving' => $moving,
    'paused' => $moving === true && file_exists('/var/run/mover.pause') === true,
    'progress' => $progress,
], JSON_INVALID_UTF8_SUBSTITUTE);
?>
