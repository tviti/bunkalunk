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

function run_segment_command(
        args::ArgDict, ctx::Context, command_map::CommandMap = SEGMENT_SUBCOMMANDS
    )::Cint
    subcommand = args["%COMMAND%"]
    subcommand !== nothing || throw(ArgumentError("No sub-command given"))

    handler = get(command_map, subcommand, nothing)
    handler !== nothing || throw(ArgumentError("Unknown subcommand $subcommand"))

    return handler(args[subcommand], ctx)
end

const COMMANDS = CommandMap(
    "segment" => run_segment_command
)

function parse_commandline()

    settings = ArgParseSettings()

    @add_arg_table! settings begin
        "--verbose", "-v"
        help = "Enable verbose output"
        action = :store_true

        "--debug"
        help = "Enable debug-level logging"
        action = :store_true

        "segment"
        action = :command
    end

    let segment_settings = settings["segment"]
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
    end

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

function run_segment_register(args::ArgDict, ctx::Context)::Cint
    force::Bool = args["force"]
    name::String = args["name"]
    path::String = abspath(args["path"])

    fingerprint = open(path, "r") do f
        compute_fingerprint(f)
    end
    @debug "Segment fingerprint: $fingerprint"

    return create_connection(ctx.db_path) do conn
        DBInterface.transaction(conn) do
            # Check for potential collisions
            column_matches = find_column_matches(conn, name, path, fingerprint)
            num_matches = length(column_matches)

            # No collisions -> cleared for takeoff
            if num_matches == 0
                insert_segment(conn, name, path, fingerprint)
                return 0
            end

            # One collision -> forcing is possible
            if num_matches == 1
                matched_column, row = first(column_matches)
                segment_id = row[:segment_id]

                if row[:name] == name &&
                        row[:definition_path] == path &&
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

                removed = remove_segment(conn, segment_id)
                removed === nothing && error("Expected segment_id=$segment_id to exist")
                remove_segment_efforts(conn, segment_id)
                insert_segment(conn, name, path, fingerprint)
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
    end
end

function run_segment_remove(args::ArgDict, ctx::Context)::Cint
    name::String = args["name"]
    create_connection(ctx.db_path) do conn
        DBInterface.transaction(conn) do
            registration = remove_segment(conn, name)
            if registration === nothing
                @info "No segment found by name $name"
                return 1
            end
            efforts = remove_segment_efforts(conn, registration[:segment_id])
            @info "Removed $(length(efforts)) segment efforts"
        end
    end
    return 0
end

function run_segment_list(args::ArgDict, ctx::Context)::Cint
    create_connection(ctx.db_path) do conn
        for reg in fetch_segment_registration(conn)
            println(ctx.io, "$(reg[:name]): $(reg[:definition_path])")
        end
    end
    return 0
end

function run_segment_match(args::ArgDict, ctx::Context)::Cint
    segment_name::String = args["name"]
    sport::Union{String, Nothing} = args["sport"]
    return create_connection(ctx.db_path) do db_conn
        segment_reg = fetch_segment_registration(db_conn, segment_name)
        segment_id::Int64 = segment_reg[:segment_id]

        fingerprint = open(segment_reg[:definition_path], "r") do f
            return compute_fingerprint(f)
        end
        if fingerprint != segment_reg[:definition_fingerprint]
            @error (
                "Segment $segment_name changed on disk (fingerprint mismatch). " *
                    "Re-register to purge old efforts, then try again."
            )
            return 1
        end

        segment = read_segment(segment_reg[:definition_path])
        activities = select_all(db_conn, sport = sport)
        activities_data = load_activities(activities)

        match_results = match_to_activities(segment, activities_data)
        for (; activity_date, activity_id, segment_time, matched_at) in match_results
            upsert_segment_effort(
                db_conn,
                activity_id,
                segment_id,
                segment_time,
                matched_at,
                matcher_version
            )
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

    efforts = create_connection(ctx.db_path) do conn
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

    println(ctx.io, "")
    println(ctx.io, repeat("-", 55))
    println(ctx.io, "  Segment name: $segment_name")
    println(ctx.io, "  $num_efforts efforts total")
    println(ctx.io, "")
    @printf(ctx.io, "  %-4s  %-24s  %11s\n", "Rank", "Activity Date", "Segment Time")
    println(repeat("-", 55))

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
        @printf(ctx.io, "  %-4s  %-24s  %11s\n", i, start_time_iso, hms_string)
        i = i + 1
        if i > top
            break
        end
    end

    return 0
end

const SEGMENT_SUBCOMMANDS = Dict{String, Function}(
    "register" => run_segment_register,
    "remove" => run_segment_remove,
    "list" => run_segment_list,
    "match" => run_segment_match,
    "show" => run_segment_show,
)

function main()
    args = parse_commandline()

    if get(args, "debug", false)
        global_logger(ConsoleLogger(stderr, Logging.Debug))
    end

    isdir(BUNK_HOME) || throw(ArgumentError("BUNK_HOME does not exist: $BUNK_HOME"))

    isdir(ACTIVITY_STORE) || throw(ArgumentError("ACTIVITY_STORE does not exist: $ACTIVITY_STORE"))

    ctx = Context(
        BUNK_HOME * "/db.sqlite3",
        ACTIVITY_STORE,
        args["verbose"]
    )

    exit_code = run_command(args, ctx)
    return exit(exit_code)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
