using ArgParse
using Lunk

function main()
    db_path = BUNK_HOME * "/db.sqlite3"
    args = parse_commandline()
    for arg in args
        println("Argument: ", arg)
    end
    return
end

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
            required = false
            action = :store_arg
            help = "Segment name. Omit to infer from segment file."

            "path"
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

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
