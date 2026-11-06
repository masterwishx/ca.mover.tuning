<?PHP
// The logs and summaries age_mover has written, newest first, as name => path.
// It writes to the configured folder, or to /tmp when that folder is empty, relative or cannot be used, so both are read.
function moverLogFiles(array $cfg): array {
  $parent = $cfg['loggingFolder'] ?? '';
  $parents = substr($parent, 0, 1) === '/' ? [rtrim($parent, '/'), '/tmp'] : ['/tmp'];
  $files = [];
  foreach (array_unique($parents) as $folder) {
    $names = @scandir("$folder/ca.mover.tuning");
    foreach (is_array($names) === true ? $names : [] as $name) {
      if (preg_match('/\A(Mover_tuning|Debug_Mover_tuning|Summary)_\d{4}-\d{2}-\d{2}T\d{6}\.(log|txt)\z/', $name) === 1) {
        $files[$name] = "$folder/ca.mover.tuning/$name";
      }
    }
  }
  uksort($files, function ($a, $b) {
    return [moverLogStamp($b), strpos($a, 'Mover_tuning') === 0 ? 0 : 1] <=> [moverLogStamp($a), strpos($b, 'Mover_tuning') === 0 ? 0 : 1];
  });
  return $files;
}

// The run's start in a log name, e.g. 2026-11-07T000001
function moverLogStamp(string $name): string {
  return substr($name, strrpos($name, '_') + 1, 17);
}

// Picker text, e.g. "2026-11-07 00:00:01 – Debug log"; needs the page's _()
function moverLogLabel(string $name): string {
  $kinds = ['Mover_tuning' => _('Mover log'), 'Debug_Mover_tuning' => _('Debug log'), 'Summary' => _('Summary')];
  $stamp = moverLogStamp($name);
  $kind = substr($name, 0, strrpos($name, '_'));
  return substr($stamp, 0, 10) . ' ' . implode(':', str_split(substr($stamp, 11), 2)) . ' – ' . ($kinds[$kind] ?? $kind);
}
?>
