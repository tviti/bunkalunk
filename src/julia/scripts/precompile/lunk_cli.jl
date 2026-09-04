const PRECOMPILE_BUNK_HOME = mktempdir(; cleanup = true)
const PRECOMPILE_ACTIVITY_STORE = joinpath(PRECOMPILE_BUNK_HOME, "activity_store")
const MATCHING_CACHE_KWARGS = (
    time = [0.0, 10.0, 20.0, 30.0],
    latitude = [-0.00005, 0.00005, 0.00015, 0.00025],
    longitude = [0.0, 0.0, 0.0, 0.0],
    heart_rate = [99.0, 99.0, 99.0, 99.0],
    elevation = [10.0, 11.0, 12.0, 13.0],
    distance = [0.0, 1.0, 2.0, 3.0],
    speed = [3.0, 3.1, 3.2, 3.3],
    x_min = 0.0,
    x_max = 0.0,
    y_min = -0.00005,
    y_max = 0.00025,
)
mkpath(PRECOMPILE_ACTIVITY_STORE)

ENV["BUNK_HOME"] = PRECOMPILE_BUNK_HOME

Base.exit(::Integer) = nothing
Base.exit() = nothing

using Lunk
include(joinpath(@__DIR__, "..", "..", "test", "fixtures.jl"))

const PRECOMPILE_DB_PATH = joinpath(PRECOMPILE_BUNK_HOME, BUNKALUNK_DB)

function reset_precompile_state!()::Nothing
    rm(PRECOMPILE_DB_PATH; force = true)
    rm(PRECOMPILE_ACTIVITY_STORE; recursive = true, force = true)
    mkpath(PRECOMPILE_ACTIVITY_STORE)

    cmd = `python -c "from bunkalunk import db; conn = db.create_connection('$PRECOMPILE_DB_PATH'); conn.close()"`
    run(cmd)

    return nothing
end

function seed_matching_cache!()::Nothing
    create_bunk_tables!(PRECOMPILE_DB_PATH)
    create_connection!(PRECOMPILE_DB_PATH) do conn
        make_registered_cache_file!(conn, PRECOMPILE_ACTIVITY_STORE; MATCHING_CACHE_KWARGS...)
        make_registered_cache_file!(
            conn,
            PRECOMPILE_ACTIVITY_STORE;
            fingerprint = "cache-2",
            start_time = 946598401.0,
            MATCHING_CACHE_KWARGS...
        )
    end
    return nothing
end

function write_minimal_geojson(path::String; name::String = "segment-json")::Nothing
    json = """
        {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [[0.0, 0.0], [0.0, 0.0001], [0.0, 0.0002]]
            },
            "properties": {
                "name": "$name"
            }
        }
    """
    write(path, json)
    return nothing
end

# Empty-state branches.
reset_precompile_state!()
Lunk.main(["segment", "list"])
Lunk.main(["segment", "show", "missing-segment"])
Lunk.main(["segment", "remove", "missing-segment"])
try
    Lunk.main(["segment", "match", "missing-segment"])
catch e
    e isa ArgumentError || rethrow()
end
try
    Lunk.main(["activity", "show"])
catch e
    e isa ArgumentError || rethrow()
end
try
    Lunk.main(["activity", "match"])
catch e
    e isa ArgumentError || rethrow()
end
Lunk.main(["activity", "match", "99"])
Lunk.main(["activity", "export", "--output", joinpath(PRECOMPILE_BUNK_HOME, "missing.csv"), "99"])

# Segment registration, collision handling, and the populated list branch.
reset_precompile_state!()
segment_path = joinpath(PRECOMPILE_BUNK_HOME, "segment.osm")
bad_segment_path = joinpath(PRECOMPILE_BUNK_HOME, "bad-segment.osm")
collision_segment_path = joinpath(PRECOMPILE_BUNK_HOME, "collision-segment.osm")
nameless_segment_path = joinpath(PRECOMPILE_BUNK_HOME, "nameless-segment.osm")
write_minimal_osm(segment_path; name = "segment")
write(
    bad_segment_path,
    "<osm><way id=\"1\" visible=\"true\"><nd ref=\"1\" /><tag k=\"name\" v=\"segment\" /></way></osm>"
)
write_minimal_osm(collision_segment_path; name = "segment-alt")
write_minimal_osm(nameless_segment_path; name = nothing)
Lunk.main(["segment", "register", segment_path])
Lunk.main(["segment", "list"])
Lunk.main(["segment", "register", bad_segment_path])
Lunk.main(["segment", "register", nameless_segment_path])
Lunk.main(["segment", "register", "--name", "segment", collision_segment_path])
Lunk.main(["segment", "register", "--force", "--name", "segment", collision_segment_path])

# Matching, export, show, and removal against real activity/cache pairs.
seed_matching_cache!()

match_export_path = joinpath(PRECOMPILE_BUNK_HOME, "segment-match.csv")
bad_match_export_path = joinpath(PRECOMPILE_BUNK_HOME, "segment-match.txt")
activity_export_path = joinpath(PRECOMPILE_BUNK_HOME, "activity.csv")

Lunk.main(["activity", "match", "1"])
Lunk.main(["activity", "match", "1", "--update"])
Lunk.main(["activity", "match"])
Lunk.main(["activity", "show", "1"])
Lunk.main(["activity", "show"])
Lunk.main(["segment", "match", "segment"])
Lunk.main(["segment", "match", "segment", "--export", bad_match_export_path])
Lunk.main(["segment", "match", "segment", "--export", match_export_path])
Lunk.main(["segment", "show", "segment", "--top", "1"])
Lunk.main(["activity", "export", "--output", activity_export_path, "1"])
Lunk.main(["segment", "remove", "segment"])

# JSON segment-file registration and matching.
reset_precompile_state!()
geojson_segment_path = joinpath(PRECOMPILE_BUNK_HOME, "segment.geojson")
write_minimal_geojson(geojson_segment_path)
Lunk.main(["segment", "register", geojson_segment_path])
seed_matching_cache!()
Lunk.main(["segment", "match", "segment-json"])

reset_precompile_state!()
for args in [
        ["--help"],
        ["segment", "--help"],
        ["segment", "match", "--help"],
        ["activity", "--help"],
        ["activity", "match", "--help"],
        ["activity", "show", "--help"],
        ["activity", "export", "--help"],
    ]
    try
        Lunk.main(args)
    catch e
        e isa MethodError || rethrow()
    end
end
