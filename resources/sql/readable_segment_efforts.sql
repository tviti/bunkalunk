/* Present segment efforts for a given segment_id, with human-readable
   start time and elapsed time. Edit the literal in the WHERE clause
   to target a different segment; the temp table is dropped at
   session end. */
DROP TABLE IF EXISTS segment_efforts_readable;
CREATE TEMP TABLE segment_efforts_readable AS
SELECT
    se.effort_id,
    se.activity_id,
    se.segment_id,
	s.name,
    strftime('%Y-%m-%dT%H:%M:%fZ', a.start_time, 'unixepoch') AS start_time_iso,
    printf(
        '%02d:%02d:%05.2f',
        CAST(se.elapsed_time_s / 3600 AS INTEGER),
        CAST((se.elapsed_time_s / 60) % 60 AS INTEGER),
        se.elapsed_time_s % 60
    ) AS elapsed_time_hms,
    se.elapsed_time_s,
    se.matched_at,
    se.matcher_version
FROM segment_efforts se
JOIN activities a ON a.activity_id = se.activity_id
JOIN segments s ON s.segment_id = se.segment_id
WHERE s.name = :segment_name;

SELECT * FROM segment_efforts_readable
ORDER BY elapsed_time_s;
