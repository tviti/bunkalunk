using Test
using SQLite
using Lunk

function make_context(dir; io = IOBuffer())
    db_path = dir * "/db.sqlite3"
    activity_store_path = dir
    verbose = false
    return Lunk.Context(db_path, activity_store_path, verbose, io)
end

@testset "run_command" begin
    # Happy path
    mktempdir() do dir
        args = Dict(
            "%COMMAND%" => "segment",
            "segment" => Dict()
        )
        ctx = make_context(dir)
        called = Ref(false)
        command_map = Lunk.CommandMap(
            "segment" => (x, y) -> begin
                called[] = true
                return "fake result"
            end
        )
        @test Lunk.run_command(args, ctx, command_map) == "fake result"
        @test called[]
    end

    # Unknown command throws
    mktempdir() do dir
        args = Dict(
            "%COMMAND%" => "not-segment",
            "not-segment" => Dict()
        )
        ctx = make_context(dir)
        command_map = Lunk.CommandMap(
            "segment" => (x, y) -> begin
                return "fake result"
            end
        )
        @test_throws ArgumentError Lunk.run_command(args, ctx, command_map)
    end

    # No command throws
    mktempdir() do dir
        args::Dict{String, Any} = Dict(
            "%COMMAND%" => nothing
        )
        ctx = make_context(dir)
        command_map = Lunk.CommandMap("segment" => (x, y) -> return)
        @test_throws ArgumentError Lunk.run_command(args, ctx, command_map)
    end
end

@testset "run_segment_command dispatches subcommands" begin
    mktempdir() do dir
        ctx = make_context(dir)
        called = Ref("")
        subcommand_map = Lunk.CommandMap(
            "register" => (x, y) -> begin
                called[] = "register"; return
            end,
            "list" => (x, y) -> begin
                called[] = "list"; return
            end,
            "match" => (x, y) -> begin
                called[] = "match"; return
            end,
            "show" => (x, y) -> begin
                called[] = "show"; return
            end,
        )
        args = Dict("%COMMAND%" => "list", "list" => Dict())
        Lunk.run_segment_command(args, ctx, subcommand_map)
        @test called[] == "list"
    end

    mktempdir() do dir
        ctx = make_context(dir)
        args::Dict{String, Any} = Dict("%COMMAND%" => nothing)
        subcommand_map = Lunk.CommandMap()
        @test_throws ArgumentError Lunk.run_segment_command(args, ctx, subcommand_map)
    end

    mktempdir() do dir
        ctx = make_context(dir)
        args = Dict("%COMMAND%" => "bogus", "bogus" => Dict())
        subcommand_map = Lunk.CommandMap()
        @test_throws ArgumentError Lunk.run_segment_command(args, ctx, subcommand_map)
    end
end

@testset "run_segment_register" begin
    # Happy path
    mktempdir() do dir
        ctx = make_context(dir)
        args::Dict{String, Any} = Dict(
            "name" => "segment",
            "path" => dir * "/segment.osm"
        )
        write(args["path"], "test")
        fingerprint = open(args["path"], "r") do f
            compute_fingerprint(f)
        end

        Lunk.run_segment_register(args, ctx)

        row = create_connection(ctx.db_path) do conn
            result = DBInterface.execute(
                conn,
                "SELECT * FROM segments WHERE name = ?",
                ["segment"]
            )
            return only(NamedTuple(r) for r in result)
        end
        @test row[:name] == "segment"
        @test row[:definition_path] == dir * "/segment.osm"
        @test row[:definition_fingerprint] == fingerprint
    end

    # run_segment_register always saves an abspath
    mktempdir() do dir
        ctx = make_context(dir)
        args::Dict{String, Any} = Dict(
            "name" => "segment",
            "path" => "./segment.osm"
        )

        cd(dir) do
            write(args["path"], "test")
            Lunk.run_segment_register(args, ctx)
        end

        row = create_connection(ctx.db_path) do conn
            result = DBInterface.execute(
                conn,
                "SELECT * FROM segments WHERE name = \"segment\""
            )
            return only(NamedTuple(r) for r in result)
        end

        @test isabspath(row[:definition_path])
    end
end

@testset "run_command segment match" begin
    @test_skip "stub: match activities against segment"
end

@testset "run_command segment show" begin
    @test_skip "stub: show segment leaderboard"
end
