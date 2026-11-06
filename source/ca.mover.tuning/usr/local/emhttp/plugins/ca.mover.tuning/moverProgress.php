<?PHP
// The running move for MoverTuningProgress.page, null when none: whether it can be paused and is (age_mover's
// mover.moving names its pid while files move), and its progress from the status file age_mover and Unraid 7.4's mover write.
// A status file whose MoverPid is not the live pid in /var/run/mover.pid is left over from another run: no progress.
header('Content-Type: application/json');
$pid = trim((string)@file_get_contents('/var/run/mover.pid'));
if (ctype_digit($pid) === false || is_dir("/proc/$pid") === false) {
    echo 'null';
    exit;
}
// as age_mover's pauseWindow: a Mover Tuning run while it moves files and no soft stop is asked (a soft stop always wins
// over a pause), or a run the plugin started through with_scripts (Unraid's mover, the per-share Move), never one
// Unraid started itself
$parent = preg_match('/^PPid:\s+(\d+)/m', (string)@file_get_contents("/proc/$pid/status"), $match) === 1 ? $match[1] : '';
$wrapped = $parent !== '' && strpos((string)@file_get_contents("/proc/$parent/cmdline"), '/ca.mover.tuning/with_scripts') !== false;
$moving = $wrapped === true || (strtok((string)@file_get_contents('/var/run/mover.moving'), ' ') === $pid && file_exists('/var/run/moversoft.stop') === false);
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
    // the pause file names the run it pauses: one left by an earlier run pauses nothing
    'paused' => $moving === true && trim((string)@file_get_contents('/var/run/mover.pause')) === $pid,
    'progress' => $progress,
], JSON_INVALID_UTF8_SUBSTITUTE);
?>
