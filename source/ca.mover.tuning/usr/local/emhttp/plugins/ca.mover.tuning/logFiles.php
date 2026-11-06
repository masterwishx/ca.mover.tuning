<?PHP
// The logs and summaries age_mover has written, newest first, as name => path.
// It writes to the configured folder, or to /tmp when that folder is empty, relative or cannot be used, so both are read.
function moverLogFiles(array $cfg): array {
  $parent = $cfg['loggingFolder'] ?? '';
  $parents = substr($parent, 0, 1) === '/' ? [rtrim($parent, '/'), '/tmp'] : ['/tmp'];
  $files = [];
  foreach (array_unique($parents) as $folder) {
    foreach (@scandir("$folder/ca.mover.tuning") ?: [] as $name) {
      if (preg_match('/\A(Mover_tuning|Debug_Mover_tuning|Summary)_\d{4}-\d{2}-\d{2}T\d{6}\.(log|txt)\z/', $name) === 1) {
        $files[$name] = "$folder/ca.mover.tuning/$name";
      }
    }
  }
  uksort($files, function ($a, $b) {
    $stamp = fn($name) => substr($name, strrpos($name, '_') + 1, 17);
    return [$stamp($b), strpos($a, 'Mover_tuning') === 0 ? 0 : 1] <=> [$stamp($a), strpos($b, 'Mover_tuning') === 0 ? 0 : 1];
  });
  return $files;
}
?>
