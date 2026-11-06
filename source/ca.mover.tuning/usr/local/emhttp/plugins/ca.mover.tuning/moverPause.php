<?PHP
// The Pause and Resume buttons of MoverTuningProgress.page; age_mover pauses only a run that is moving files
$action = $_POST['action'] ?? '';
if ($action === 'pause') {
    exec('/usr/local/emhttp/plugins/ca.mover.tuning/age_mover pause'); // nosemgrep
} elseif ($action === 'resume') {
    exec('/usr/local/emhttp/plugins/ca.mover.tuning/age_mover resume'); // nosemgrep
}
?>
