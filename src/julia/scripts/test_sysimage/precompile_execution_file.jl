const PRECOMPILE_BUNK_HOME = mktempdir(; cleanup = true)
const PRECOMPILE_ACTIVITY_STORE = joinpath(PRECOMPILE_BUNK_HOME, "activity_store")
const MATCHING_CACHE_KWARGS = (
    time = [0.0, 10.0, 20.0, 30.0],
    latitude = [-0.00005, 0.00005, 0.00015, 0.00025],
    longitude = [0.0, 0.0, 0.0, 0.0],
    heart_rate = nothing,
    elevation = nothing,
    distance = nothing,
    speed = nothing,
)
mkpath(PRECOMPILE_ACTIVITY_STORE)

ENV["BUNK_HOME"] = PRECOMPILE_BUNK_HOME

Base.exit(::Integer) = nothing
Base.exit() = nothing

using Lunk
include(joinpath(@__DIR__, "..", "..", "test", "fixtures.jl"))

const PRECOMPILE_DB_PATH = joinpath(PRECOMPILE_BUNK_HOME, BUNKALUNK_DB)

function fire_lunk(args::Vector{String})::Nothing
    try
        Lunk.main(args)
    catch
    end
    return nothing
end

function reset_precompile_state!()::Nothing
    rm(PRECOMPILE_DB_PATH; force = true)
    rm(PRECOMPILE_ACTIVITY_STORE; recursive = true, force = true)
    mkpath(PRECOMPILE_ACTIVITY_STORE)

    cmd = `python -c "from bunkalunk import db; conn = db.create_connection('$PRECOMPILE_DB_PATH'); conn.close()"`
    process = run(cmd)
    process.exitcode == 0 || throw(
        Error(
            "Got exit code $process.exitcode while trying to initialize bunk db"
        )
    )

    return nothing
end

function seed_matching_cache!()::Nothing
    create_connection!(PRECOMPILE_DB_PATH) do conn
        create_activities_table!(conn)
        make_registered_cache_file!(conn, PRECOMPILE_ACTIVITY_STORE; MATCHING_CACHE_KWARGS...)
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
fire_lunk(["segment", "list"])
fire_lunk(["segment", "show", "missing-segment"])
fire_lunk(["segment", "remove", "missing-segment"])
fire_lunk(["segment", "match", "missing-segment"])
fire_lunk(["activity", "export", "--output", joinpath(PRECOMPILE_BUNK_HOME, "missing.csv"), "99"])

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
fire_lunk(["segment", "register", segment_path])
fire_lunk(["segment", "list"])
fire_lunk(["segment", "register", bad_segment_path])
fire_lunk(["segment", "register", nameless_segment_path])
fire_lunk(["segment", "register", "--name", "segment", collision_segment_path])
fire_lunk(["segment", "register", "--force", "--name", "segment", collision_segment_path])

# Matching, export, show, and removal against a real activity/cache pair.
seed_matching_cache!()

match_export_path = joinpath(PRECOMPILE_BUNK_HOME, "segment-match.csv")
bad_match_export_path = joinpath(PRECOMPILE_BUNK_HOME, "segment-match.txt")
activity_export_path = joinpath(PRECOMPILE_BUNK_HOME, "activity.csv")

fire_lunk(["segment", "match", "segment"])
fire_lunk(["segment", "match", "segment", "--export", bad_match_export_path])
fire_lunk(["segment", "match", "segment", "--export", match_export_path])
fire_lunk(["segment", "show", "segment", "--top", "1"])
fire_lunk(["activity", "export", "--output", activity_export_path, "1"])
fire_lunk(["segment", "remove", "segment"])

# JSON segment-file registration and matching.
reset_precompile_state!()
geojson_segment_path = joinpath(PRECOMPILE_BUNK_HOME, "segment.geojson")
write_minimal_geojson(geojson_segment_path)
fire_lunk(["segment", "register", geojson_segment_path])
seed_matching_cache!()
fire_lunk(["segment", "match", "segment-json"])

reset_precompile_state!()
fire_lunk(["--help"])
fire_lunk(["segment", "--help"])
fire_lunk(["segment", "match", "--help"])
fire_lunk(["activity", "--help"])
fire_lunk(["activity", "export", "--help"])
