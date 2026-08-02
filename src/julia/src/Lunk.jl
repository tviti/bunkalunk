module Lunk

include("cache.jl")
export CacheData, drop_cache_points, find_valid_points, read_cache

include("paths.jl")
export BUNKALUNK_DB, resolve_activity_store, resolve_bunk_home, resolve_cache_path

include("segments.jl")
export Segment, compute_fingerprint, read_segment

include("db.jl")
export create_connection!, fetch_segment_efforts_by_name, fetch_segment_efforts_by_pairing,
    fetch_segment_names, fetch_segment_registration,
    fetch_segment_registration_by_fingerprint, fetch_segment_registration_by_name,
    fetch_segment_registration_by_path, get_content_fingerprint, insert_segment!,
    insert_segment_effort!, remove_segment!, remove_segment_efforts!, select_all,
    select_by_id, select_by_start_date, select_by_time_range, select_overlapping

include("geo.jl")
export compute_ecef_r, crosses_gate, haversine_distance, linterp, on_polyline

include("match.jl")
export ActivityContext, MatchResult, load_activities, match_to_activities, matcher_version

include("export.jl")
export GeoCSV, write_geocsv!

include("cli.jl")
end
