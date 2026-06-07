module Lunk

include("cache.jl")
export CacheData,
    read_cache,
    filter_track_nans

include("paths.jl")
export BUNK_HOME,
    ACTIVITY_STORE,
    resolve_cache_path

include("db.jl")
export create_connection,
    get_content_fingerprint,
    select_by_start_date,
    select_by_time_range,
    upsert_segment,
    upsert_segment_effort,
    fetch_segment_path,
    fetch_segment_names

include("segments.jl")
export Segment,
    read_segment,
    compute_fingerprint

include("geo.jl")
export compute_ecef_r,
    crosses_gate,
    on_polyline,
    haversine_distance

include("cli.jl")
end
