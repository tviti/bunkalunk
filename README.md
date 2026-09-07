# Bunkalunk

Bunkalunk is a pair of command line programs for matching fitness tracker
activities to geographic segments, and creating segment time leaderboards.

`bunk`, the ingest application, decodes and serializes fitness tracker files to
an HDF5 cache. `lunk`, the leaderboard application, includes commands for
registering segment files, matching activities to segments (vice versa), and
exporting decoded activities to GeoCSV. Together, `bunk` and `lunk` can be used
with GIS programs like GDAL and QGIS, to create a flexible segment timing and
data inspection workflow. Ingest files with `bunk`, then inspect tracks exported
by `lunk` in a GIS GUI. Define segments for the portions you want to time,
register them with `lunk`, then run `lunk segment match <segment name>` to build
the segment’s leaderboard. When new activities are added to Bunkalunk, run
`lunk activity match` to match them against the segment registry.

I developed Bunkalunk primarily to time mountainbike rides. I wanted to race
myself without buying into a cloud service, and uploading the tracks for hidden
trails. I also wanted to do “stuff” with my activity data, without being stuck
working with it on a per-file basis. The Bunkalunk db is SQLite, and the cache
is HDF5, so it's easy to explore the catalog and work with activities in
batches. Both formats are widely supported, and the schemas used are relatively
simple, so in theory it's easy to use them outside of Bunkalunk (like a one-off
script to plot speed leading up to a crash).
  
## Usage

Bunkalunk stores system state, including SQLite DB and decoded activity cache,
at `${HOME}/.bunk`. You can override this location by setting the environment variable
`BUNK_HOME`.

### Adding Files

Register and decode new activity files using `bunk add`

```
$ bunk add path/to/fit-files/*
```

The `add` command takes one or more arguments , so multiple files can be
ingested using shell expansions/globs (`add` is _not_ recursive though). The
decoded activity data is stored in a deduplicated cache, so if you accidentally
download an activity from your cloud service that was already decoded, it will
not be re-decoded a second time (assuming the downloaded file is
byte-identical).

### Working With Segments

Register a new segment using `lunk segment register`

```
$ lunk segment register path/to/segments/my-segment.geojson
```

The segment registry stores a hash of the segment file contents, in order to
detect drift. If you edit a segment, you'll need to re-register it, otherwise
subsequent `lunk` commands acting on it will either warn you of the discrepancy,
or fail outright if they need the original registered data (e.g. to match
against).

```
$ lunk segment register --force path/to/segments/my-segment.geojson
```

You can view the currently registered segments using the `list` command

```
$ lunk segment list
  ID    Name                            Path
  ----  ------------------------------  -----------
  1     Half-mile from home             /home/taylor/leaderboard-project/segments/29th-garfield-to-circle29th.geojson
  2     700 With a View                 /home/taylor/leaderboard-project/segments/700-with-a-view.geojson
  3     Alpha                           /home/taylor/leaderboard-project/segments/alpha.geojson
```

Use the `segment match` command to scan the activity store for matches and
update the efforts table, then use the `segment show` command to view the
segment's leaderboard.

```
$ lunk segment match "Half-mile from home"
$ lunk segment show --sport=cycling "Half-mile from home"

  -----------------------------------------
   Segment name: Half-mile from home
   Distance: 0.8106 km (0.5037 mi)
   28 efforts total
  -----------------------------------------

  Rank  Activity Date          Time
  ----  -------------------    ------------
  1     2025-03-21T00:54:26    2:0.3039
  2     2025-02-16T20:33:17    2:0.6395
  3     2024-12-17T23:01:34    2:5.9846
  4     2025-02-25T15:25:01    2:6.2781
  5     2026-04-28T19:06:18    2:6.3219
  6     2025-02-06T02:56:33    2:6.4994
  7     2026-04-17T00:42:07    2:6.6452
  8     2026-07-14T17:14:44    2:9.4998
  9     2026-03-13T21:22:08    2:9.5555
  10    2026-03-09T23:18:30    2:9.8405
$ lunk segment show --sport=running "Half-mile from home"

  -----------------------------------------
   Segment name: Half-mile from home
   Distance: 0.8106 km (0.5037 mi)
   12 efforts total
  -----------------------------------------

  Rank  Activity Date          Time
  ----  -------------------    ------------
  1     2026-02-20T18:17:11    3:58.2715
  2     2026-04-02T18:22:17    3:58.9916
  3     2026-02-23T21:10:08    4:9.0432
  4     2025-11-29T20:26:11    4:13.6575
  5     2025-11-05T22:34:11    4:16.4260
  6     2026-07-02T18:36:58    4:31.8147
  7     2026-07-12T20:03:59    4:39.1786
  8     2026-07-07T18:49:41    4:43.0462
  9     2025-12-15T22:51:27    4:47.1800
  10    2026-07-09T18:41:38    4:48.7054
```

### Working With Activities

Use the `activity match` command to scan the registry for matching segments, and
add the activity's efforts to the database. Pass `--update` to re-scan the
entire activity cache for new matches to the found segments, useful if you want
to make sure that the rankings from `activity show` are up-to-date.

Both commands accept an optional `activity-id`, if you know exactly which
activity you want to look at. With no `activity-id`, they use activity with the
most recent timestamp.

```
$ lunk activity match --update
$ lunk activity show

  -----------------------------------------
   Start time:  2026-09-05T20:56:46
   Activity ID: 490
   Sport:       cycling
   Distance:    19.8699 km (12.3466 mi)
   Elevation:
     Min:       109.6 m (359.6 ft)
     Max:       666.8 m (2187.7 ft)
     Gain:      839.8 m (2755.2 ft)
     Loss:      827.8 m (2715.9 ft)
   Speed:
     Median:    6.36 km/h (3.95 mph)
     Max:       37.15 km/h (23.08 mph)
   Heart Rate:
     Median:    164.0 bpm
     Min:       97.0 bpm
     Max:       184.0 bpm
  -----------------------------------------

  Segment Name                   Rank      Time
  -------------------------      --------  ------------
  As You Wish (Upper)            31/42     5:42.0323
  As You Wish (Lower)            23/36     1:52.7295
  New Groove                     21/28     3:32.0825
  700 With a View                29/42     5:21.4510
  Narnia                         36/48     2:27.3395
  Login                          74/95     12:0.7502
```

### Data Sources
  
If you use a cloud service like Garmin Connect or Strava, you should start by
using the platform's data dump feature to download all of your activity
data. From there, you can manually add new data to the store straight from your
fitness tracker. If you’re using a Garmin device and a Linux OS, this can be as
simple as mounting the device over USB using `mtpfuse`, and rsync-ing the data
to your storage directory.

## Limitations

- `bunk` only ingests Garmin Activity FIT files. GPX support is planned but not
  yet implemented.
- `lunk` only registers OSM and GeoJSON formatted segment files. I've
  contemplated adding GPX support but haven't found a good use case yet.
- GeoJSON segment files must contain a single `Feature` whose `geometry.type` is
  `"LineString"`.
- `bunk add` accepts multiple paths but is non-recursive. Globbing is left to
  the shell program.
- `lunk` does not validate activity data. If the decode artifact schema changes,
  the user must manually delete and regenerate the `segment_efforts` table.

## Who is Bunkalunk?
  
Bunkalunk is my cat. Bunkalunk is a high quality chunk, and a tiny little
skunk. His full name is Benoit, but he usually just goes by Ben. Bunkalunk is
usually sitting next to me while I work on this project, hence the name.
  
He is the loudest, most obnoxious and needy creature I have ever shared
a space with. He is also the most doting, affectionate, patient, and
unconditionally loving one I have ever met. I have never known a cat to so badly
want to be friends as Bunkalunk does, and I want to do my best every day to make
sure he knows that he is indeed a friend (usually after he’s done stomping
around the house and howling for attention).
