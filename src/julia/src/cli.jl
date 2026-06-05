using ArgParse
using Lunk

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

        "segment"
        action = :command
    end

    let segment_settings = settings["segment"]
        @add_arg_table! segment_settings begin
            "register"
            action = :command
            help = "Add a new segment to the database."

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
            "name"
            required = true
            action = :store_arg
            help = "Segment name."

            "path"
            required = true
            action = :store_arg
            help = "Path to segment file."
        end

        @add_arg_table! segment_settings["match"] begin
            "name"
            required = true
            action = :store_arg
            help = "Segment name."
        end

        @add_arg_table! segment_settings["show"] begin
            "name"
            required = true
            action = :store_arg
            help = "Segment name."
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

function run_segment_register(args::ArgDict, ctx::Context)::Cint
    name::String = args["name"]
    path::String = abspath(args["path"])

    fingerprint = open(path, "r") do f
        compute_fingerprint(f)
    end

    create_connection(ctx.db_path) do conn
        upsert_segment(conn, name, path, fingerprint)
    end

    return 0
end

function run_segment_list(args::ArgDict, ctx::Context)::Cint
    create_connection(ctx.db_path) do conn
        names = fetch_segment_names(conn)
        for name in names
            path = fetch_segment_path(conn, name)
            println(ctx.io, "$name: $path")
        end
    end
    return 0
end

function run_segment_match(args::ArgDict, ctx::Context)::Cint
    throw(ArgumentError("lunk segment match: not yet implemented"))
end

function run_segment_show(args::ArgDict, ctx::Context)::Cint
    throw(ArgumentError("lunk segment show: not yet implemented"))
end

const SEGMENT_SUBCOMMANDS = Dict{String, Function}(
    "register" => run_segment_register,
    "list" => run_segment_list,
    "match" => run_segment_match,
    "show" => run_segment_show,
)

function main()
    args = parse_commandline()

    isdir(BUNK_HOME) || throw(ArgumentError("BUNK_HOME does not exist: $BUNK_HOME"))

    isdir(ACTIVITY_STORE) || throw(ArgumentError("ACTIVITY_STORE does not exist: $ACTIVITY_STORE"))

    ctx = Context(
        BUNK_HOME * "/db.sqlite3",
        ACTIVITY_STORE,
        args["verbose"]
    )

    exit_code = run_command(args, ctx)
    exit(exit_code)

    return
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
