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

function run_subcommand(
        args::ArgDict, ctx::Context, command_map::CommandMap
    )::Cint
    subcommand = args["%COMMAND%"]
    subcommand !== nothing || throw(ArgumentError("No sub-command given"))

    handler = get(command_map, subcommand, nothing)
    handler !== nothing || throw(ArgumentError("Unknown subcommand $subcommand"))

    return handler(args[subcommand], ctx)
end

function run_segment_subcommand(
        args::ArgDict, ctx::Context, command_map::CommandMap = SEGMENT_SUBCOMMANDS
    )::Cint
    return run_subcommand(args, ctx, command_map)
end

function run_activity_subcommand(
        args::ArgDict, ctx::Context, command_map::CommandMap = ACTIVITY_SUBCOMMANDS
    )::Cint
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

        "--debug"
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
        "register"
        action = :command
        help = """Add a new segment to the database. Supports OSM XML files
        and GeoJSON. Only supports GeoJSON Feature file-types with
        LineString geometry, all other rejected. Generate using ogr2ogr with
        GeoJSONSeq formatted output."""

        "remove"
        action = :command
        help = "Remove a segment and its efforts from the database."

        "rename"
        action = :command
        help = "Rename a segment in the database."

        "list"
        action = :command
        help = "List all registered segments."

        "match"
        action = :command
        help = "Run match and timing calculations."

        "show"
        action = :command
        help = "Show segment efforts."
    end

    @add_arg_table! segment_settings["register"] begin
        "--force"
        help = "Force overwrite of an existing segment"
        action = :store_true

        "name"
        required = true
        action = :store_arg
        help = "Segment name."

        "path"
        required = true
        action = :store_arg
        help = "Path to segment file."
    end

    @add_arg_table! segment_settings["remove"] begin
        "name"
        required = true
        action = :store_arg
        help = "Segment name."
    end

    @add_arg_table! segment_settings["match"] begin
        "name"
        required = true
        action = :store_arg
        help = "Segment name."

        "sport"
        required = false
        action = :store_arg
        default = nothing
        help = "Match only activities with this sport."

        "--export"
        required = false
        action = :store_arg
        arg_type = String
        help = "Export match data to a GeoCSV + CSVT at the given path."
    end

    @add_arg_table! segment_settings["show"] begin
        "name"
        required = true
        action = :store_arg
        help = "Segment name."

        "--top"
        arg_type = Int
        action = :store_arg
        default = 10
        help = "Number of efforts to show."
    end

    return
end

function add_activities_argtable!(settings::ArgParseSettings)::Nothing
    activity_settings = settings["activity"]
    @add_arg_table! activity_settings begin
        "export"
        action = :command
        help = "Export a list of activities to GeoCSV + CSVT sidecar."
    end

    @add_arg_table! activity_settings["export"] begin
        "activity_ids"
        nargs = '+'
        required = true
        action = :store_arg
        arg_type = Int
        help = "The activities to be included in the export."

        "--output", "-o"
        required = true
        action = :store_arg
        help = "Output path."
    end
    return
end

function parse_commandline()

    description = """Lunk: the bunkalunk leaderboard application.
    """

    settings = ArgParseSettings(
        prog = "Lunk",
        description = description
    )

    add_root_argtable!(settings)
    add_segment_argtable!(settings)
    add_activities_argtable!(settings)

    return parse_args(settings)
end

function run_command(
        args::ArgDict, ctx::Context, command_map::CommandMap = COMMANDS
    )::Cint
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

function find_column_matches(
        conn::SQLite.DB, name::String, path::String, fingerprint::String
    )::Vector{Tuple{String, Any}}
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
    )
    # Check for potential collisions
    column_matches = find_column_matches(conn, name, path, fingerprint)
    num_matches = length(column_matches)

    # No collisions -> cleared for takeoff
    if num_matches == 0
        insert_segment!(conn, name, path, fingerprint)
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
        insert_segment!(conn, name, path, fingerprint)
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

function run_segment_register(args::ArgDict, ctx::Context)::Cint
    force::Bool = args["force"]
    name::String = args["name"]
    path::String = abspath(args["path"])

    # Verify that the segment is decodable
    try
        read_segment(path)
    catch e
        showerror(ctx.io, e)
        @error "Segment at $path could not be decoded"
        return 1
    end

    fingerprint = open(path, "r") do f
        compute_fingerprint(f)
    end
    @debug "Segment fingerprint: $fingerprint"

    return create_connection!(ctx.db_path) do conn
        DBInterface.transaction(conn) do
            segment_register_transaction(conn, name, path, fingerprint, force)
        end
    end
end

function run_segment_remove(args::ArgDict, ctx::Context)::Cint
    name::String = args["name"]
    create_connection!(ctx.db_path) do conn
        DBInterface.transaction(conn) do
            registration = remove_segment!(conn, name)
            if registration === nothing
                @info "No segment found by name $name"
                return 1
            end
            efforts = remove_segment_efforts!(conn, registration[:segment_id])
            @info "Removed $(length(efforts)) segment efforts"
        end
    end
    return 0
end

function run_segment_list(args::ArgDict, ctx::Context)::Cint
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

function is_stale_segment(
        segment_name::String, definition_path::String, definition_fingerprint::String
    )::Bool
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

function load_matcher_inputs(
        db_conn::SQLite.DB, definition_path::String, sport::Union{String, Nothing}
    )::Tuple{Segment, Dict{Int, CacheData}}
    segment = read_segment(definition_path)
    activities = select_all(db_conn, sport = sport)
    activities_data = load_activities(activities)
    return (segment, activities_data)
end

function accumulate_geocsv_data!(
        g::GeoCSV, match::MatchResult
    )::Nothing
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
    )::Union{GeoCSV, Nothing}

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
            matcher_version
        )
        if export_path !== nothing
            accumulate_geocsv_data!(export_data, match)
        end
    end
    @debug "Persisted $(length(match_results)) segment efforts"
    return export_data
end

function run_segment_match(args::ArgDict, ctx::Context)::Cint
    segment_name::String = args["name"]
    sport::Union{String, Nothing} = args["sport"]
    export_path::Union{String, Nothing} = args["export"]

    if export_path !== nothing
        _, ext = splitext(export_path)
        if ext != ".csv"
            @error "Unrecognized file extension, got $ext"
            return 1
        end
    end

    return create_connection!(ctx.db_path) do db_conn
        segment_reg = fetch_segment_registration(db_conn, segment_name)
        segment_id::Int64 = segment_reg[:segment_id]
        definition_path = segment_reg[:definition_path]

        if is_stale_segment(
                segment_name, definition_path, segment_reg[:definition_fingerprint]
            )
            return 1
        end

        (segment, activities_data) = load_matcher_inputs(
            db_conn, definition_path, sport
        )

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

function seconds2hms(t::Real)::Tuple{Int, Int, Real}
    t_h = divrem(t, 60)
    hours = floor(t / 3600.0)
    minutes = Int(t_h[1])
    seconds = t_h[2]
    return (hours, minutes, seconds)
end

function run_segment_show(args::ArgDict, ctx::Context)::Cint
    segment_name::String = args["name"]
    top::Int = args["top"]

    efforts = create_connection!(ctx.db_path) do conn
        fetch_segment_efforts_by_name(conn, segment_name)
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

    row_format = Printf.Format("  %-4s  %-21s  %s\n")
    println(ctx.io, "")
    println(ctx.io, repeat("-", 50))
    println(ctx.io, "  Segment name: $segment_name")
    println(ctx.io, "  $num_efforts efforts total")
    println(ctx.io, repeat("-", 50))
    println(ctx.io, "")
    Printf.format(ctx.io, row_format, "Rank", "Activity Date", "Segment Time")
    Printf.format(ctx.io, row_format, repeat("-", 4), repeat("-", 21), repeat("-", 15))

    i = 1
    for (; effort_id, start_time, activity_id, elapsed_time_s) in efforts
        start_time_iso = unix2datetime(start_time)
        hms_string = let (h, m, s) = seconds2hms(elapsed_time_s)
            if h != 0
                @sprintf("%d:%d:%0.4f", h, m, s)
            else
                @sprintf("%d:%0.4f", m, s)
            end
        end
        Printf.format(ctx.io, row_format, i, start_time_iso, hms_string)
        i = i + 1
        if i > top
            break
        end
    end

    return 0
end

function accumulate_geocsv_data!(
        g::GeoCSV, activity_id::Int, cache::CacheData
    )::Nothing
    for (x, y, t) in zip(cache.longitude, cache.latitude, cache.time)
        push!(g.x, x)
        push!(g.y, y)
        push!(g.time, unix2datetime(t))
        push!(g.fields[1], activity_id)
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

function run_activity_export(args::ArgDict, ctx::Context)::Cint
    activity_ids::Vector{Int64} = args["activity_ids"]
    output::String = abspath(args["output"])

    _, ext = splitext(output)
    if ext != ".csv"
        @error "Unrecognized file extension, got $ext"
        return 1
    end

    errors = Int64[]
    export_data = GeoCSV(
        Float64[],
        Float64[],
        DateTime[],
        [Int64[]],
        ["activity_id"]
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
                cache_path = resolve_cache_path(fingerprint, ctx.activity_store)
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
    "export" => run_activity_export,
)

function main()
    args = parse_commandline()

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
