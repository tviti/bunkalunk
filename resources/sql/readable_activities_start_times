/* Present activity start time in human readable format. */
SELECT *, datetime(start_time, 'unixepoch', 'localtime') as start_time_iso
FROM activities
ORDER BY -start_time