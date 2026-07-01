const PRECOMPILE_BUNK_HOME = mktempdir(; cleanup = true)
const PRECOMPILE_ACTIVITY_STORE = joinpath(PRECOMPILE_BUNK_HOME, "activity_store")
mkpath(PRECOMPILE_ACTIVITY_STORE)

ENV["BUNK_HOME"] = PRECOMPILE_BUNK_HOME

Base.exit(::Integer) = nothing
Base.exit() = nothing

using Lunk
include(joinpath(@__DIR__, "..", "test", "fixtures.jl"))

const PRECOMPILE_CTX = Lunk.Context(
    joinpath(PRECOMPILE_BUNK_HOME, "db.sqlite3"),
    PRECOMPILE_ACTIVITY_STORE,
    false
)

function fire_lunk(args::Vector{String}, ctx::Lunk.Context)::Nothing
    original_args = copy(ARGS)
    try
        empty!(ARGS)
        append!(ARGS, args)
        try
            parsed = Lunk.parse_commandline()
            Lunk.run_command(parsed, ctx)
        catch
        end
    finally
        empty!(ARGS)
        append!(ARGS, original_args)
    end
    return nothing
end

function reset_precompile_state!()::Nothing
    db_path = joinpath(PRECOMPILE_BUNK_HOME, "db.sqlite3")
    isfile(db_path) && rm(db_path; force = true)
    isdir(PRECOMPILE_ACTIVITY_STORE) && rm(PRECOMPILE_ACTIVITY_STORE; recursive = true, force = true)
    mkpath(PRECOMPILE_ACTIVITY_STORE)

    cmd = `python -c "from bunkalunk import db; conn = db.create_connection('$db_path'); conn.close()"`
    process = run(cmd)
    process.exitcode == 0 || throw(
        Error(
            "Got exit code $process.exitcode while trying to initialize bunk db"
        )
    )

    return nothing
end

function write_minimal_osm(path::String; name::String = "segment")::Nothing
    xml = """
        <osm>
            <node id="1" visible="true" lat="0.0" lon="0.0" />
            <node id="2" visible="true" lat="0.0001" lon="0.0" />
            <node id="3" visible="true" lat="0.0002" lon="0.0" />
            <way id="1" visible="true">
                <nd ref="1" />
                <nd ref="2" />
                <nd ref="3" />
                <tag k="name" v="$name" />
            </way>
        </osm>
    """
    write(path, xml)
    return nothing
end

function make_matching_cache_file!(conn::SQLite.DB, dir::String; fingerprint::String = "cache")::String
    create_activities_table!(conn)
    insert_activity!(
        conn,
        Dict(
            :start_time => 946598400.0,
            :source_fingerprint => fingerprint,
            :ride_tag => nothing,
            :sport => "cycling",
            :cache_version => 20260624,
        )
    )

    cache_dir = joinpath(dir, fingerprint[1:2])
    mkpath(cache_dir)
    path = joinpath(cache_dir, fingerprint * ".h5")
    h5open(path, "w") do file
        file["time"] = [0.0, 10.0, 20.0, 30.0]
        file["latitude"] = [-0.00005, 0.00005, 0.00015, 0.00025]
        file["longitude"] = [0.0, 0.0, 0.0, 0.0]
        attributes(file)["start_time"] = 946598400.0
        attributes(file)["sport"] = "cycling"
    end
    return path
end

function Lunk.load_activities(
        activities::Vector{Tuple{Int, String}}
    )::Dict{Int, CacheData}
    return Dict(
        id => read_cache(resolve_cache_path(fingerprint, PRECOMPILE_ACTIVITY_STORE))
            for (id, fingerprint) in activities
    )
end

# Empty-state branches.
reset_precompile_state!()
fire_lunk(["segment", "list"], PRECOMPILE_CTX)
fire_lunk(["segment", "show", "missing-segment"], PRECOMPILE_CTX)
fire_lunk(["segment", "remove", "missing-segment"], PRECOMPILE_CTX)
fire_lunk(["segment", "match", "missing-segment"], PRECOMPILE_CTX)
fire_lunk(["activity", "export", "--output", joinpath(PRECOMPILE_BUNK_HOME, "missing.csv"), "99"], PRECOMPILE_CTX)

# Segment registration, collision handling, and the populated list branch.
reset_precompile_state!()
segment_path = joinpath(PRECOMPILE_BUNK_HOME, "segment.osm")
bad_segment_path = joinpath(PRECOMPILE_BUNK_HOME, "bad-segment.osm")
collision_segment_path = joinpath(PRECOMPILE_BUNK_HOME, "collision-segment.osm")
write_minimal_osm(segment_path; name = "segment")
write(
    bad_segment_path,
    "<osm><way id=\"1\" visible=\"true\"><nd ref=\"1\" /><tag k=\"name\" v=\"segment\" /></way></osm>"
)
write_minimal_osm(collision_segment_path; name = "segment-alt")
fire_lunk(["segment", "register", "segment", segment_path], PRECOMPILE_CTX)
fire_lunk(["segment", "list"], PRECOMPILE_CTX)
fire_lunk(["segment", "register", "segment", bad_segment_path], PRECOMPILE_CTX)
fire_lunk(["segment", "register", "segment", collision_segment_path], PRECOMPILE_CTX)
fire_lunk(["segment", "register", "--force", "segment", collision_segment_path], PRECOMPILE_CTX)

# Matching, export, show, and removal against a real activity/cache pair.
create_connection!(joinpath(PRECOMPILE_BUNK_HOME, "db.sqlite3")) do conn
    make_matching_cache_file!(conn, PRECOMPILE_ACTIVITY_STORE)
end

match_export_path = joinpath(PRECOMPILE_BUNK_HOME, "segment-match.csv")
bad_match_export_path = joinpath(PRECOMPILE_BUNK_HOME, "segment-match.txt")
activity_export_path = joinpath(PRECOMPILE_BUNK_HOME, "activity.csv")

fire_lunk(["segment", "match", "segment"], PRECOMPILE_CTX)
fire_lunk(["segment", "match", "segment", "--export", bad_match_export_path], PRECOMPILE_CTX)
fire_lunk(["segment", "match", "segment", "--export", match_export_path], PRECOMPILE_CTX)
fire_lunk(["segment", "show", "segment", "--top", "1"], PRECOMPILE_CTX)
fire_lunk(["activity", "export", "--output", activity_export_path, "1"], PRECOMPILE_CTX)
fire_lunk(["segment", "remove", "segment"], PRECOMPILE_CTX)
