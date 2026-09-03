# Bunkalunk

Bunkalunk is a pair of command line programs for matching fitness tracker
activities to geographic segments, and creating segment time leader boards.

`bunk`, the ingest application, decodes and serializes fitness tracker files to
an hdf5 cache. `lunk`, the leader board application, includes commands for
registering segments files, matching activities to segments (vice versa), and
exporting decoded activities to GeoCSV. Together, `bunk` and `lunk` can be used
with GIS programs like GDAL and QGIS, to create a flexible segment timing and
data inspection workflow. Ingest files with `bunk`, then inspect tracks exported
by `lunk` in a GIS GUI. Define segments for the portions you want to time,
register them with `lunk`, then run `lunk segment match <segment name>` to build
the segment’s leader board. When new activities are added to Bunkalunk, run
`lunk activity match` to match them against the segment registry.

I developed Bunkalunk primarily to time mountainbike rides. I wanted to race
myself without buying into a cloud service, and uploading the tracks for hidden
trails. I also wanted to do “stuff” with my activity data, without being stuck
working with it on a per-file basis. The Bunkalunk db is SQLite, and the cache
is HDF5, so its easy to explore the catalog and work with activities in
batches. Both formats are widely supported, and the schemas used are relatively
simple, so in theory it's easy to use them outside of Bunkalunk (like a one-off
script to plot speed leading up to a crash).
  
## Usage

```
$ bunk add path/to/fit-files/*  # Ingest all files in a directory
$ lunk segment add path/to/segments/segment.geojson --name="Segment Name" # Add a segment to the segment registry
$ lunk segment list  # Show all the names of the registered segments
$ lunk segment match "Segment Name"  # Find matches and calculate segment times for Segment Name
$ lunk segment show "Segment Name" # Render the leaderboard for Segment Name
$ lunk activity match [--update] [activity-id]  # Find matches for [activity-id] (omit to select most recent activity)
$ lunk activity show [activity-id]  # Render a report for [activity-id] including segment times
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
  
Bunkalunk is a high quality chunk, and a tiny little skunk. His full name is
Benoit, but he usually just goes by Ben.
  
He is the loudest, most obnoxious and needy creature I have ever had the shared
a space with. He is also the most doting, affectionate, patient, and
unconditionally loving one I have ever met. I have never known a cat to so badly
want to be friends as Bunkalunk does, and I want to do my best every day to make
sure he knows that he is indeed a friend (usually after he’s done stomping
around the house and howling for attention).
