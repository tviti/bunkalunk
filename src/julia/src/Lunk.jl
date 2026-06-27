module Lunk

include("cache.jl")
export CacheData,
    read_cache,
    drop_invalid_gps_points

include("paths.jl")
export resolve_bunk_home,
    resolve_activity_store,
    resolve_cache_path

include("db.jl")
export create_connection!,
    get_content_fingerprint,
    select_by_start_date,
    select_by_time_range,
    select_by_id,
    select_all,
    insert_segment!,
    insert_segment_effort!,
    fetch_segment_registration,
    fetch_segment_names,
    fetch_segment_registration_by_name,
    fetch_segment_registration_by_fingerprint,
    fetch_segment_registration_by_path,
    remove_segment!,
    remove_segment_efforts!,
    fetch_segment_efforts_by_name

include("segments.jl")
export Segment,
    read_segment,
    compute_fingerprint

include("geo.jl")
export compute_ecef_r,
    crosses_gate,
    on_polyline,
    haversine_distance,
    linterp

include("match.jl")
export load_activities,
    match_to_activities,
    matcher_version,
    MatchResult

include("export.jl")
export write_geocsv!,
    GeoCSV

include("cli.jl")
end
