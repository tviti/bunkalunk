using ArgParse
using Logging
using Lunk
using SQLite
using Dates
using Printf

const ArgDict = Dict{String, Any}
const CommandMap = Dict{String, Function}

struct Context
    db_path::String
    activity_store::String
    verbose::Bool
    io::IO
end

function Context(db_path::String, activity_store::String, verbose::Bool)
    return Context(db_path, activity_store, verbose, stdout)
end

function Context()
    return Context(
        joinpath(resolve_bunk_home(), BUNKALUNK_DB),
        resolve_activity_store(),
        false
    )
end

function run_subcommand(
        args::ArgDict, ctx::Context, command_map::CommandMap
    )
    subcommand = args["%COMMAND%"]
    subcommand !== nothing || throw(ArgumentError("No sub-command given"))

    handler = get(command_map, subcommand, nothing)
    handler !== nothing || throw(ArgumentError("Unknown subcommand $subcommand"))

    return handler(args[subcommand], ctx)
end

function run_segment_subcommand(
        args::ArgDict, ctx::Context, command_map::CommandMap = SEGMENT_SUBCOMMANDS
    )
    return run_subcommand(args, ctx, command_map)
end

function run_activity_subcommand(
        args::ArgDict, ctx::Context, command_map::CommandMap = ACTIVITY_SUBCOMMANDS
    )
    return run_subcommand(args, ctx, command_map)
end

const COMMANDS = CommandMap(
    "segment" => run_segment_subcommand,
    "activity" => run_activity_subcommand
)

function add_root_argtable!(settings::ArgParseSettings)::Nothing
    @add_arg_table! settings begin
        "--verbose", "-v"
        help = "Enable verbose output"
        action = :store_true

        "--debug", "-d"
        help = "Enable debug-level logging"
        action = :store_true

        "segment"
        help = "Subcommands acting on a segment"
        action = :command

        "activity"
        help = "Subcommands acting on activities"
        action = :command
    end
    return
end

function add_segment_argtable!(settings::ArgParseSettings)::Nothing
    segment_settings = settings["segment"]

    @add_arg_table! segment_settings begin
        "register", "add"
        action = :command
        help = """Add a new segment to the database. Supports OSM XML files
        and GeoJSON. Only supports GeoJSON Feature file-types with
        LineString geometry, all other rejected. Generate using ogr2ogr with
        GeoJSONSeq formatted output."""

        "remove", "rm"
        action = :command
        help = "Remove a segment and its efforts from the database"

        "rename", "mv"
        action = :command
        help = "Rename a segment in the database"

        "list", "ls"
        action = :command
        help = "List all registered segments"

        "match"
        action = :command
        help = "Run match and timing calculations"

        "show"
        action = :command
        help = "Show segment efforts"
    end

    @add_arg_table! segment_settings["register"] begin
        "--force", "-f"
        help = "Force overwrite of an existing segment"
        action = :store_true

        "--name", "-n"
        action = :store_arg
        arg_type = String
        help = "Segment name"

        "path"
        required = true
        action = :store_arg
        arg_type = String
        help = "Path to segment file"
    end

    @add_arg_table! segment_settings["remove"] begin
        "name"
        required = true
        action = :store_arg
        help = "Segment name"
    end

    @add_arg_table! segment_settings["match"] begin
        "name"
        required = true
        action = :store_arg
        help = "Segment name"

        "--export", "-e"
        required = false
        action = :store_arg
        arg_type = String
        help = "Export match data to a GeoCSV + CSVT at the given path"
    end

    @add_arg_table! segment_settings["show"] begin
        "name"
        required = true
        action = :store_arg
        help = "Segment name"

        "--top", "-t"
        arg_type = Int
        action = :store_arg
        default = 10
        help = "Number of efforts to show"

        "--sport", "-s"
        required = false
        action = :store_arg
        default = nothing
        help = "Show only matches with the given sport"
    end

    return
end

function add_activities_argtable!(settings::ArgParseSettings)::Nothing
    activity_settings = settings["activity"]
    @add_arg_table! activity_settings begin
        "match"
        action = :command
        help = "Run match and timing calculations on an activity"

        "show"
        action = :command
        help = "Show an activity's segment efforts"

        "export"
        action = :command
        help = "Export a list of activities to GeoCSV + CSVT sidecar"
    end

    @add_arg_table! activity_settings["match"] begin
        "activity_id"
        required = false
        action = :store_arg
        arg_type = Int
        help = "The activity to match, omit to match most recent"

        "--update"
        action = :store_true
        help = "Update each matched segment's rankings"
    end

    @add_arg_table! activity_settings["show"] begin
        "activity_id"
        required = false
        action = :store_arg
        arg_type = Int
        help = "The activity to show, omit to show most recent"
    end

    @add_arg_table! activity_settings["export"] begin
        "activity_ids"
        nargs = '+'
        required = true
        action = :store_arg
        arg_type = Int
        help = "The activities to be included in the export"

        "--output", "-o"
        required = true
        action = :store_arg
        help = "Output path"
    end
    return
end

function parse_commandline(argv::Vector{String})

    description = """Lunk: the bunkalunk leaderboard application.
    """

    settings = ArgParseSettings(
        prog = "Lunk",
        description = description
    )

    add_root_argtable!(settings)
    add_segment_argtable!(settings)
    add_activities_argtable!(settings)

    return parse_args(argv, settings)
end

function run_command(
        args::ArgDict, ctx::Context, command_map::CommandMap = COMMANDS
    )
    command = args["%COMMAND%"]

    command !== nothing || throw(
        ArgumentError(
            "run_command called but no command given"
        )
    )

    handler = get(command_map, command, nothing)
    handler !== nothing || throw(ArgumentError("Unknown command $command"))

    return handler(args[command], ctx)
end

function run_command(argv::Vector{String})
    args = parse_commandline(argv)
    ctx = Context(
        resolve_bunk_home() * "/db.sqlite3",
        resolve_activity_store(),
        false
    )
    return run_command(args, ctx)
end


function find_column_matches(
        conn::SQLite.DB, name::String, path::String, fingerprint::String
    )
    by_name = fetch_segment_registration_by_name(conn, name)
    by_path = fetch_segment_registration_by_path(conn, path)
    by_fingerprint = fetch_segment_registration_by_fingerprint(conn, fingerprint)

    column_matches = Tuple{String, Any}[]
    by_name === nothing || push!(column_matches, ("name", by_name))
    by_path === nothing || push!(column_matches, ("path", by_path))
    by_fingerprint === nothing || push!(column_matches, ("fingerprint", by_fingerprint))

    segment_ids = [row[:segment_id] for (_, row) in column_matches]
    unique_indices = indexin(unique(segment_ids), segment_ids)

    return column_matches[unique_indices]
end

function segment_register_transaction(
        conn::SQLite.DB,
        name::String,
        path::String,
        fingerprint::String,
        force::Bool,
        segment::Segment
    )
    # Check for potential collisions
    column_matches = find_column_matches(conn, name, path, fingerprint)
    num_matches = length(column_matches)

    # No collisions -> cleared for takeoff
    if num_matches == 0
        insert_segment!(conn, name, path, fingerprint, segment)
        return 0
    end

    # One collision -> forcing is possible
    if num_matches == 1
        matched_column, row = first(column_matches)
        segment_id = row[:segment_id]

        if row[:name] == name && row[:definition_path] == path &&
                row[:definition_fingerprint] == fingerprint
            @info(
                "Segment '$name' already registered with this path and " *
                    "content; no change.\n" *
                    "(To force a full re-registration and purge " *
                    "segment_efforts, run\n" *
                    " `lunk segment remove $name` followed by " *
                    "`lunk segment register ...`.)"
            )
            return 0
        end

        if !force
            if matched_column == "name"
                value = name
            elseif matched_column == "path"
                value = path
            else
                value = fingerprint
            end
            @error """
            $matched_column '$value' already registered as segment_id=$segment_id
                   (name=$(row[:name]), path=$(row[:definition_path])).
            Re-run with --force to replace.
            """
            return 1
        end

        remove_segment_efforts!(conn, segment_id)
        removed = remove_segment!(conn, segment_id)
        removed === nothing && error("Expected segment_id=$segment_id to exist")
        insert_segment!(conn, name, path, fingerprint, segment)
        return 0
    end

    details = join(
        [
            "  $column -> segment_id=$(row[:segment_id]) " *
                "(name=$(row[:name]), path=$(row[:definition_path]), " *
                "fingerprint=$(row[:definition_fingerprint]))"
                for (column, row) in column_matches
        ],
        "\n"
    )
    @error (
        "registration would replace $num_matches distinct existing segments:\n" *
            details * "\n" *
            "Resolve manually with `lunk segment remove` before retrying."
    )
    return 1

end

"""
    segment_register(
        path::String; name::Union{String, Nothing} = nothing, force::Bool = false, ctx = Context()
    )

Register a new segment in the database.

If `name` is `nothing`, attempts to register using the name read from the segment
file.

"""
function segment_register(
        path::String; name::Union{String, Nothing} = nothing, force::Bool = false, ctx = Context()
    )
    # Verify that the segment is decodable
    segment::Segment = try
        read_segment(path)
    catch e
        showerror(ctx.io, e)
        @error "Segment at $path could not be decoded"
        return 1
    end

    if name !== nothing
        registered_name = name
    elseif segment.name != ""
        registered_name = segment.name
    else
        @error "Could not determine name for segment at $path"
        return 1
    end

    fingerprint = open(path, "r") do f
        compute_fingerprint(f)
    end
    @debug "Segment fingerprint: $fingerprint"

    return create_connection!(ctx.db_path) do conn
        DBInterface.transaction(conn) do
            segment_register_transaction(
                conn, registered_name, path, fingerprint, force, segment
            )
        end
    end
end

function run_segment_register(args::ArgDict, ctx::Context)
    force::Bool = args["force"]
    name::Union{String, Nothing} = args["name"]
    path::String = abspath(args["path"])
    return segment_register(path; name = name, force = force, ctx = ctx)
end

function segment_remove(name::String; ctx = Context())
    create_connection!(ctx.db_path) do conn
        DBInterface.transaction(conn) do
            registration = fetch_segment_registration_by_name(conn, name)
            if registration === nothing
                @info "No segment found by name $name"
                return 1
            end
            efforts = remove_segment_efforts!(conn, registration[:segment_id])
            @info "Removed $(length(efforts)) segment efforts"
            remove_segment!(conn, name)
        end
    end
    return 0
end

function run_segment_remove(args::ArgDict, ctx::Context)
    name::String = args["name"]
    return segment_remove(name; ctx = ctx)
end

function segment_list(; ctx = Context())
    row_fmt = Printf.Format("  %-4s  %-30s  %s\n")
    Printf.format(ctx.io, row_fmt, "ID", "Name", "Path")
    Printf.format(
        ctx.io, row_fmt,
        repeat("-", 4),
        repeat("-", 30),
        repeat("-", 11)
    )
    return create_connection!(ctx.db_path) do conn
        regs = fetch_segment_registration(conn)
        if isempty(regs)
            println(ctx.io, "No segments registered.")
            return 0
        end
        for reg in fetch_segment_registration(conn)
            Printf.format(
                ctx.io, row_fmt,
                reg[:segment_id],
                reg[:name],
                reg[:definition_path]
            )
        end
        return 0
    end
end

function run_segment_list(args::ArgDict, ctx::Context)
    return segment_list(ctx = ctx)
end

function is_stale_segment(
        segment_name::String, definition_path::String, definition_fingerprint::String
    )
    fingerprint = open(definition_path, "r") do f
        return compute_fingerprint(f)
    end
    if fingerprint != definition_fingerprint
        @error (
            "Segment $segment_name changed on disk (fingerprint mismatch). " *
                "Re-register to purge old efforts, then try again."
        )
        return true
    end
    return false
end

function load_segment_match_inputs(
        db_conn::SQLite.DB,
        segment_registration::SegmentRegistration
    )
    (; x_min, y_min, x_max, y_max, segment_id) = segment_registration
    activities = select_overlapping(
        db_conn, x_min, y_min, x_max, y_max; only_unmatched_to = segment_id
    )

    segment = read_segment(segment_registration[:definition_path])
    activities_data = load_activities(activities)

    return (segment, activities_data)
end

function accumulate_geocsv_data!(
        g::GeoCSV, match::MatchResult
    )::Nothing
    num_fields = length(g.field_names)
    num_matches = length(match.match_points)
    activity_id = match.activity_id
    for (p, t) in zip(match.match_points, match.match_times)
        push!(g.x, p[1])
        push!(g.y, p[2])
        push!(g.time, unix2datetime(t))
        push!(g.fields[1], activity_id)
    end
    return
end

function segment_match_transaction!(
        db_conn::SQLite.DB,
        segment_id::Int64,
        match_results::Vector{MatchResult},
        export_path::Union{String, Nothing}
    )
    if export_path !== nothing
        export_data = GeoCSV(
            Float64[],
            Float64[],
            DateTime[],
            [Int64[]],
            ["activity_id"]
        )
    else
        export_data = nothing
    end

    # Clean up existing efforts first
    efforts = NamedTuple[]
    for activity_id in unique(m.activity_id for m in match_results)
        removed = remove_segment_efforts!(db_conn, segment_id, activity_id)
        append!(efforts, removed)
    end

    @debug "Removed $(length(efforts)) segment efforts"
    for match in match_results
        insert_segment_effort!(
            db_conn,
            match.activity_id,
            segment_id,
            match.segment_time,
            match.matched_at,
            matcher_version,
            match.idx_start,
            match.idx_end
        )
        if export_path !== nothing
            accumulate_geocsv_data!(export_data, match)
        end
    end
    @debug "Persisted $(length(match_results)) segment efforts"
    return export_data
end

function run_segment_match(args::ArgDict, ctx::Context)
    segment_name::String = args["name"]
    export_path::Union{String, Nothing} = args["export"]
    return segment_match(
        segment_name;
        ctx = ctx,
        export_path = export_path
    )
end

function segment_match(
        segment_name::String;
        ctx = Context(),
        export_path::Union{String, Nothing} = nothing
    )
    if export_path !== nothing
        _, ext = splitext(export_path)
        if ext != ".csv"
            @error "Unrecognized file extension, got $ext"
            return 1
        end
    end

    return create_connection!(ctx.db_path) do db_conn
        segment_reg = fetch_segment_registration(db_conn, segment_name)
        segment_id = segment_reg[:segment_id]
        definition_path = segment_reg[:definition_path]

        if is_stale_segment(
                segment_name, definition_path, segment_reg[:definition_fingerprint]
            )
            return 1
        end

        (segment, activities_data) = load_segment_match_inputs(db_conn, segment_reg)

        match_results = match_to_activities(segment, activities_data)
        export_data = DBInterface.transaction(db_conn) do
            segment_match_transaction!(
                db_conn,
                segment_id,
                match_results,
                export_path
            )
        end
        if export_path !== nothing
            try
                write_geocsv_atomic!(export_path, export_data)
            catch e
                showerror(ctx.io, e)
                @error "Failed during export to $export_path"
                return 1
            end
        end
        return 0
    end
end

"""
    seconds2hms(t::Float64)

Convert `t` in seconds to a `Tuple` `(hours, minutes, seconds)`.
"""
function seconds2hms(t::Float64)
    t_h = divrem(t, 60)
    hours = floor(Int64, t / 3600.0)
    minutes = Int64(t_h[1])
    seconds = t_h[2]
    return (hours, minutes, seconds)
end

function hms2string(h, m, s)
    return if h != 0
        @sprintf("%d:%d:%0.4f", h, m, s)
    else
        @sprintf("%d:%0.4f", m, s)
    end
end

"""
    hms2string(t::Float64)

Convert `t` in seconds to an `h:m:s` string. If `t` is less than one hour in
duration, the output string is instead formatted `m:s`.
"""
function hms2string(t::Real)
    return hms2string(seconds2hms(Float64(t))...)
end

function run_segment_show(args::ArgDict, ctx::Context)
    segment_name::String = args["name"]
    top::Int = args["top"]
    sport::Union{String, Nothing} = args["sport"]
    return segment_show(segment_name; top = top, sport = sport, ctx = ctx)
end

"""
    segment_show(segment_name::String; ctx = Context(), top = Int64(10), sport = sport)

Show a table of segment efforts for `segment_name`
"""
function segment_show(
        segment_name::String;
        ctx = Context(),
        top = Int64(10),
        sport::Union{String, Nothing} = nothing
    )

    efforts, registration = create_connection!(ctx.db_path) do conn
        (
            fetch_segment_efforts_by_name(conn, segment_name, sport = sport),
            fetch_segment_registration_by_name(conn, segment_name),
        )
    end

    if registration === nothing
        @error "No segment is registered under $segment_name"
        return 1
    end

    if is_stale_segment(
            segment_name,
            registration[:definition_path],
            registration[:definition_fingerprint]
        )
        return 1
    end

    num_efforts = length(efforts)
    if num_efforts == 0
        println("No efforts for segment $segment_name")
        return 0
    end

    max_hours_ago = 24.0
    today = datetime2unix(Dates.now())
    stale = [today - row[:matched_at] > max_hours_ago * 3600 for row in efforts]
    if any(stale)
        @warn (
            "Warning: $(sum(stale)) of $num_efforts efforts are older than " *
                "$max_hours_ago hours, re-run `lunk segment match` to ensure efforts are up to date"
        )
    end

    stale_matcher = [row[:matcher_version] != matcher_version for row in efforts]
    if any(stale_matcher)
        @warn (
            "Warning: $(sum(stale_matcher)) of $num_efforts efforts use an old matcher algorithm " *
                ", re-run `lunk segment match` to ensure efforts are up to date"
        )
    end

    segment = read_segment(registration[:definition_path])
    distance = let diffs = Float64[]
        for i in 1:(length(segment.longitude) - 1)
            p1 = (segment.latitude[i], segment.longitude[i])
            p2 = (segment.latitude[i + 1], segment.longitude[i + 1])
            push!(diffs, haversine_distance(p1, p2))
        end
        sum(diffs)
    end

    row_format = Printf.Format("  %-4s  %-21s  %s\n")
    println(ctx.io, "")
    println(ctx.io, "  " * repeat("-", 41))
    println(ctx.io, "   Segment name: $segment_name")
    @printf(ctx.io, "   Distance: %.4f km (%.4f mi)\n", 1.0e-3 * distance, meters2miles(distance))
    println(ctx.io, "   $num_efforts efforts total")
    println(ctx.io, "  " * repeat("-", 41))
    println(ctx.io, "")
    Printf.format(ctx.io, row_format, "Rank", "Activity Date", "Time")
    Printf.format(ctx.io, row_format, repeat("-", 4), repeat("-", 19), repeat("-", 12))

    i = 1
    for (; effort_id, start_time, activity_id, elapsed_time_s) in efforts
        start_time_iso = unix2datetime(start_time)
        hms_string = hms2string(elapsed_time_s)
        Printf.format(ctx.io, row_format, i, start_time_iso, hms_string)
        i = i + 1
        if i > top
            break
        end
    end

    return 0
end

"""
    activity_match_update!(
        db::SQLite.DB,
        registration::SegmentRegistration,
        segment_ecef::Matrix{Float64},
        payload_cache::ActivitiesPayload
    )

Run the matcher over the segment described by `registration` and its precomputed
ECEF matrix `segment_ecef`. Pre-existing efforts are not recomputed unless they
have a stale `matcher_version`. The `ActivityContext` data for each of the found
activity candidates are cached to `payload_cache`, such that under repeated
calls with the same input `payload_cache`, activities already seen are not
re-processed.
"""
function activity_match_update!(
        db::SQLite.DB,
        registration::SegmentRegistration,
        segment_ecef::Matrix{Float64},
        payload_cache::ActivitiesPayload
    )
    (; x_min, y_min, x_max, y_max, segment_id) = registration
    activities = select_overlapping(
        db, x_min, y_min, x_max, y_max; only_unmatched_to = segment_id
    )

    activity_ids = Int64[]
    for (activity_id, fingerprint) in activities
        if !(activity_id in keys(payload_cache))
            payload_cache[activity_id] =
                fingerprint |> load_activity |> ActivityContext
        end
        push!(activity_ids, activity_id)
    end

    payload = ActivitiesPayload(id => payload_cache[id] for id in activity_ids)

    return match_to_activities(segment_ecef, payload)
end

function activity_match_transaction!(
        db::SQLite.DB,
        registration::SegmentRegistration,
        segment_ecef::Matrix{Float64},
        activity_payload::ActivitiesPayload,
        payload_cache::ActivitiesPayload,
        update::Bool,
        io::IO
    )
    activity_id = only(keys(activity_payload))
    (; segment_id, name) = registration

    removed_efforts = remove_segment_efforts!(
        db, segment_id, activity_id; only_stale = true
    )
    existing_efforts = fetch_segment_efforts_by_pairing(
        db, segment_id, activity_id
    )

    @debug "Removed $(length(removed_efforts)) segment efforts "

    # TODO: Future work should implement a dual to match_to_activities that
    # matches multiple segments against a single activity, and can check N
    # segments for matches simultaneously (within the same loop over M track
    # points, instead of running a worst-case MxN iterations like the
    # current design).
    if isempty(existing_efforts)
        match_results = match_to_activities(segment_ecef, activity_payload)

        if isempty(match_results)
            return 0
        end

        segment_match_transaction!(
            db,
            segment_id,
            match_results,
            nothing
        )
    end

    if update
        update_results = try
            activity_match_update!(db, registration, segment_ecef, payload_cache)
        catch e
            showerror(io, e)
            @error "Could not update activities for segment $name"
            return 1
        end

        if isempty(update_results)
            return 0
        end

        segment_match_transaction!(
            db,
            segment_id,
            update_results,
            nothing
        )
    end

    return 0
end

"""
    activity_match(activity_id::Int; ctx = Context(), update = false)

Search for segments matching `activity_id`, and insert a row to the
`segment_efforts` table for each affirmative match. Candidate segments are
aggregated by partial-overlap with the given bbox for the given
`activity_id`. For each of the candidate segments, efforts matching the
`(segment_id, activity_id)` with a stale `matcher_version` are purged. If no
existing efforts remain for that pair, the match algorithm is re-run, otherwise
it is skipped.

Set `update = true` to re-run a full corpus match for each of matched segments,
ensuring that the rankings for that segment are up to date. The full corpus
match is incremental; pre-existing efforts are not recomputed unless they are
stale.
"""
function activity_match(activity_id::Int; ctx = Context(), update = false)
    cache_fingerprint, overlapping_segments = try
        create_connection!(ctx.db_path) do db
            (
                select_by_id(db, activity_id),
                select_segments_overlapping_activity(db, activity_id),
            )
        end
    catch e
        if !(e isa ArgumentError)
            rethrow(e)
        end
        showerror(ctx.io, e)
        @error "Could not select activity with id $activity_id, row not found"
        return 1
    end

    activity_ctx = try
        cache_fingerprint |> load_activity |> ActivityContext
    catch e
        showerror(ctx.io, e)
        @error "Could not read cache for activity $activity_id"
        return 1
    end
    activity_payload = ActivitiesPayload(activity_id => activity_ctx)

    # We store the ActivityContexts calculated while iterating over
    # overlapping_segments so that they can be reused on subsequent iterations
    payload_cache = ActivitiesPayload(activity_id => activity_ctx)

    errors = Int64[]
    for registration in overlapping_segments
        (; name, definition_path, definition_fingerprint, segment_id) = registration
        if is_stale_segment(name, definition_path, definition_fingerprint)
            continue
        end

        segment = read_segment(definition_path)
        segment_ecef = compute_ecef_r(segment.latitude, segment.longitude, FIXED_HEIGHT)

        let error = create_connection!(ctx.db_path) do db
                DBInterface.transaction(db) do
                    activity_match_transaction!(
                        db,
                        registration,
                        segment_ecef,
                        activity_payload,
                        payload_cache,
                        update,
                        ctx.io
                    )
                end
            end
            if error != 0
                push!(errors, segment_id)
            end
        end
    end

    if !isempty(errors)
        return 1
    end

    return 0
end

function activity_match(; ctx = Context(), update = false)
    activity_id = create_connection!(ctx.db_path) do conn
        latest_activity(conn)
    end
    return activity_match(activity_id; ctx = ctx, update = update)
end

function run_activity_match(args::ArgDict, ctx::Context)
    activity_id = args["activity_id"]
    update = args["update"]
    if activity_id === nothing
        return activity_match(; ctx = ctx, update = update)
    end
    return activity_match(activity_id; ctx = ctx, update = update)
end

function activity_show(; ctx = Context())
    activity_id = create_connection!(ctx.db_path) do conn
        latest_activity(conn)
    end
    return activity_show(activity_id; ctx = ctx)
end

function activity_show(activity_id::Int; ctx = Context())
    start_time, segments = create_connection!(ctx.db_path) do db
        segment_ids = fetch_segment_ids_matching_activity(db, activity_id)
        segment_dict = Dict(
            id => fetch_segment_efforts_by_segment_id(db, id)
                for id in segment_ids
        )

        (activity_start_time(db, activity_id), segment_dict)
    end

    println(ctx.io, "")
    println(ctx.io, "  " * repeat("-", 41))
    println(ctx.io, "   Start time: $start_time")
    # @printf(ctx.io, "   Distance: %.4f km (%.4f mi)\n", 1.0e-3 * distance, meters2miles(distance))
    # println(ctx.io, "   $num_efforts efforts total")
    println(ctx.io, "  " * repeat("-", 41))
    println(ctx.io, "")

    row_format = Printf.Format("  %-21s %-8s  %s\n")
    Printf.format(ctx.io, row_format, "Segment Name", "Rank", "Time")
    Printf.format(ctx.io, row_format, repeat("-", 19), repeat("-", 8), repeat("-", 12))

    for (_, segment_efforts) in segments
        name = segment_efforts[1][:name]
        num_efforts = length(segment_efforts)
        activity_efforts = [
            (rank = i, time = hms2string(e[:elapsed_time_s]))
                for (i, e) in enumerate(segment_efforts)
                if e[:activity_id] == activity_id
        ]

        for effort in activity_efforts
            rank_string = "$(effort[:rank])/$num_efforts"
            Printf.format(ctx.io, row_format, "$name", rank_string, effort[:time])
        end

    end
    return 0
end

function run_activity_show(args::ArgDict, ctx::Context)
    activity_id = args["activity_id"]
    if activity_id === nothing
        return activity_show(; ctx = ctx)
    end
    return activity_show(activity_id; ctx = ctx)
end

function accumulate_geocsv_data!(
        g::GeoCSV, activity_id::Int, cache::CacheData
    )::Nothing
    num_fields = length(g.field_names)
    num_cache = length(cache.longitude)
    field_values = Union{Vector{Float64}, Vector{Int64}}[
        name == "activity_id" ? fill(activity_id, num_cache) : getfield(cache, Symbol(name))
            for name in g.field_names
    ]
    for i in 1:num_cache
        push!(g.x, cache.longitude[i])
        push!(g.y, cache.latitude[i])
        push!(g.time, unix2datetime(cache.time[i]))
        for j in 1:num_fields
            values = field_values[j]
            if values === nothing
                push!(g.fields[j], NaN)
            else
                push!(g.fields[j], values[i])
            end
        end
    end
    return
end

"""
Not truly "atomic" since it uses `mv` for the final copy-into-place, and because
there's a brief window between the CSV and CSVT write where one might exist but
not the other, but good enough for bunkalunk.
"""
function write_geocsv_atomic!(path::String, export_data::GeoCSV)::Nothing
    mktempdir(dirname(path)) do dir
        tmp_path = joinpath(dir, "tmp.csv")
        write_geocsv!(tmp_path, export_data; write_sidecar = true)
        mv(tmp_path * "t", path * "t", force = true)
        mv(tmp_path, path, force = true)
    end
    return
end

function run_activity_export(args::ArgDict, ctx::Context)
    activity_ids::Vector{Int64} = args["activity_ids"]
    output::String = abspath(args["output"])

    activity_store = ctx.activity_store

    _, ext = splitext(output)
    if ext != ".csv"
        @error "Unrecognized file extension, got $ext"
        return 1
    end

    errors = Int64[]

    export_fields = Union{Vector{Float64}, Vector{Int64}}[Int64[], Float64[], Float64[], Float64[], Float64[]]
    export_field_names = ["activity_id", "heart_rate", "elevation", "speed", "distance"]
    export_data = GeoCSV(
        Float64[],
        Float64[],
        DateTime[],
        export_fields,
        export_field_names
    )
    create_connection!(ctx.db_path) do db_conn
        for id in activity_ids
            let fingerprint,
                    cache
                try
                    fingerprint = select_by_id(db_conn, id)
                catch e
                    if e isa ArgumentError
                        showerror(ctx.io, e)
                        @error "Could not select activity with id $id, row not found"
                        push!(errors, id)
                        break
                    else
                        rethrow(e)
                    end
                end
                cache_path = resolve_cache_path(fingerprint, activity_store)
                try
                    cache = read_cache(cache_path)
                catch e
                    showerror(ctx.io, e)
                    @error "Could not read cache at $cache_path"
                    push!(errors, id)
                    break
                end
                accumulate_geocsv_data!(export_data, id, cache)

            end
        end
    end

    if length(errors) != 0
        return 1
    end

    try
        write_geocsv_atomic!(output, export_data)
    catch e
        showerror(ctx.io, e)
        @error "Failed during export to $output"
        return 1
    end

    return 0
end

# TODO: Should these maps be moved into the subcommand dispatch methods?
const SEGMENT_SUBCOMMANDS = Dict{String, Function}(
    "register" => run_segment_register,
    "remove" => run_segment_remove,
    "list" => run_segment_list,
    "match" => run_segment_match,
    "show" => run_segment_show,
)

const ACTIVITY_SUBCOMMANDS = Dict{String, Function}(
    "match" => run_activity_match,
    "show" => run_activity_show,
    "export" => run_activity_export,
)

function main(argv::Vector{String} = ARGS)
    args = parse_commandline(argv)

    if get(args, "debug", false)
        global_logger(ConsoleLogger(stderr, Logging.Debug))
    end

    isdir(resolve_bunk_home()) || throw(ArgumentError("BUNK_HOME does not exist: $resolve_bunk_home"))

    isdir(resolve_activity_store()) || throw(ArgumentError("ACTIVITY_STORE does not exist: $resolve_activity_store"))

    ctx = Context(
        resolve_bunk_home() * "/db.sqlite3",
        resolve_activity_store(),
        args["verbose"]
    )

    exit_code = run_command(args, ctx)
    return exit(exit_code)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
