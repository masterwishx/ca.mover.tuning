<?PHP
// The cron check shared by updateCron.php, which writes the cron files, and Mover.tuning.page, which flags a schedule it rejects

// Five fields of * / n / n-m lists with an optional /step, each within its range; anything else would land in root's crontab.
// dcron's @hourly..@yearly forms need an ID= job name updateCron.php does not add, so they are not accepted.
function valid_cron($cron)
{
	$fields = preg_split('/[ \t]+/', $cron);
	if (count($fields) !== 5) {
		return false;
	}
	$limits = [
		[0, 59, []],
		[0, 23, []],
		[1, 31, []],
		[1, 12, ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec']],
		[0, 7, ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']],
	];
	foreach ($fields as $i => $field) {
		if (cron_field_ok($field, $limits[$i][0], $limits[$i][1], $limits[$i][2]) === false) {
			return false;
		}
	}
	return true;
}

// One cron field: a comma list of * / n / n-m, each with an optional /step; numbers within min..max, names looked up in $names
function cron_field_ok($field, $min, $max, $names)
{
	foreach (explode(',', $field) as $item) {
		if (preg_match('/^(\*|([a-z0-9]+)(?:-([a-z0-9]+))?)(?:\/([0-9]+))?\z/i', $item, $m) !== 1) {
			return false;
		}
		if (isset($m[4]) === true && (int)$m[4] < 1) {
			return false;
		}
		if ($m[1] === '*') {
			continue;
		}
		foreach ([$m[2], $m[3] ?? ''] as $value) {
			if ($value === '') {
				continue;
			}
			// names count from $min, so jan is 1 and sun is 0
			$index = array_search(strtolower($value), $names, true);
			$n = ctype_digit($value) === true ? (int)$value : ($index === false ? -1 : $index + $min);
			if ($n < $min || $n > $max) {
				return false;
			}
		}
	}
	return true;
}

/** True when a saved schedule is set but valid_cron rejects it, so updateCron.php does not apply it */
function saved_cron_invalid($cron)
{
	$cron = trim($cron);
	return $cron !== '' && valid_cron($cron) === false;
}
?>
