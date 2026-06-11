using Test
using SQLite
using Lunk
using Logging


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
                return 0
            end
        )
        @test Lunk.run_command(args, ctx, command_map) == 0
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
                called[] = "register"; return 0
            end,
            "list" => (x, y) -> begin
                called[] = "list"; return 0
            end,
            "match" => (x, y) -> begin
                called[] = "match"; return 0
            end,
            "show" => (x, y) -> begin
                called[] = "show"; return 0
            end,
        )
        args = Dict("%COMMAND%" => "list", "list" => Dict())
        @test Lunk.run_segment_command(args, ctx, subcommand_map) == 0
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
            "force" => false,
            "name" => "segment",
            "path" => dir * "/segment.osm"
        )
        write(args["path"], "test")
        fingerprint = open(args["path"], "r") do f
            compute_fingerprint(f)
        end

        @test Lunk.run_segment_register(args, ctx) == 0

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
            "force" => false,
            "name" => "segment",
            "path" => "./segment.osm"
        )
        cd(dir) do
            write(args["path"], "test")
            @test Lunk.run_segment_register(args, ctx) == 0
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

    # run_segment_register collisions
    mktempdir() do dir
        ctx = make_context(dir)
        cd(dir) do
            segment_path = abspath(dir * "/segment.osm")
            other_path = abspath(dir * "/other.osm")
            write(segment_path, "test")
            fingerprint = open(segment_path, "r") do f
                compute_fingerprint(f)
            end
            create_connection(ctx.db_path) do conn
                DBInterface.execute(
                    conn,
                    """
                    INSERT INTO segments (
                        name,
                        definition_fingerprint,
                        definition_path
                    ) VALUES (
                        "segment",
                        ?,
                        ?
                    )
                    """,
                    [fingerprint, segment_path]
                )
            end

            # Path collision: same path, new name, new content
            write(segment_path, "new-content")
            let args = Dict{String, Any}(
                    "force" => false,
                    "name" => "new-segment",
                    "path" => segment_path
                )
                result = @test_logs (:error,) Lunk.run_segment_register(args, ctx)
                @test result == 1
                args["force"] = true
                @test Lunk.run_segment_register(args, ctx) == 0
            end

            # Name collision: same name, new path, new content
            let
                write(other_path, "other-content")
                args = Dict{String, Any}(
                    "force" => false,
                    "name" => "new-segment",
                    "path" => other_path
                )
                result = @test_logs (:error,) Lunk.run_segment_register(args, ctx)
                @test result == 1
                args["force"] = true
                @test Lunk.run_segment_register(args, ctx) == 0
            end

            # Fingerprint collision: same content, new name, new path
            let fp_path = abspath(dir * "/fp.osm")
                write(fp_path, "other-content")  # same content as "other.osm" above
                fp = open(fp_path, "r") do f
                    compute_fingerprint(f)
                end
                # Verify fingerprint matches the just-registered segment
                create_connection(ctx.db_path) do conn
                    row = Lunk.fetch_segment_registration_by_name(conn, "new-segment")
                    @test row[:definition_fingerprint] == fp
                end
                args = Dict{String, Any}(
                    "force" => false,
                    "name" => "brand-new-name",
                    "path" => fp_path
                )
                result = @test_logs (:error,) Lunk.run_segment_register(args, ctx)
                @test result == 1
                args["force"] = true
                @test Lunk.run_segment_register(args, ctx) == 0
            end
        end
    end

    # Exact match: same name, path, content -> no-op exit 0
    mktempdir() do dir
        ctx = make_context(dir)
        cd(dir) do
            path = abspath(dir * "/seg.osm")
            write(path, "test")
            args = Dict{String, Any}(
                "force" => false,
                "name" => "myseg",
                "path" => path
            )
            @test Lunk.run_segment_register(args, ctx) == 0

            old_sid = create_connection(ctx.db_path) do conn
                row = fetch_segment_registration(conn, "myseg")
                row[:segment_id]
            end
            create_connection(ctx.db_path) do conn
                DBInterface.execute(
                    conn,
                    "INSERT INTO segment_efforts (activity_id, segment_id, elapsed_time_s, matched_at, matcher_version) VALUES (1, ?, 100.0, 1234, 20260607)",
                    [old_sid]
                )
            end

            # Register again with same inputs
            args = Dict{String, Any}(
                "force" => false,
                "name" => "myseg",
                "path" => path
            )
            result = @test_logs (:info,) Lunk.run_segment_register(args, ctx)
            @test result == 0
            # Also with --force, should still be no-op
            args["force"] = true
            result = @test_logs (:info,) Lunk.run_segment_register(args, ctx)
            @test result == 0

            create_connection(ctx.db_path) do conn
                result = DBInterface.execute(
                    conn,
                    "SELECT COUNT(*) AS n FROM segment_efforts WHERE segment_id = ?",
                    [old_sid]
                )
                @test only(NamedTuple(r) for r in result).n == 1
            end
        end
    end

    # Multi-axis collision: name matches one row, path matches another
    # -> always exit 1, even with --force
    mktempdir() do dir
        ctx = make_context(dir)
        cd(dir) do
            path_a = abspath(dir * "/a.osm")
            path_b = abspath(dir * "/b.osm")
            write(path_a, "content-a")
            write(path_b, "content-b")

            let args = Dict{String, Any}(
                    "force" => false,
                    "name" => "segment-a",
                    "path" => path_a
                )
                @test Lunk.run_segment_register(args, ctx) == 0
            end

            let args = Dict{String, Any}(
                    "force" => false,
                    "name" => "segment-b",
                    "path" => path_b
                )
                @test Lunk.run_segment_register(args, ctx) == 0
            end

            original_rows = create_connection(ctx.db_path) do conn
                fetch_segment_registration(conn)
            end

            @test length(original_rows) == 2
            @test original_rows[1][:name] == "segment-a"
            @test original_rows[2][:name] == "segment-b"

            collision_args = Dict{String, Any}(
                "force" => false,
                "name" => "segment-a",
                "path" => path_b
            )
            result = @test_logs (:error,) Lunk.run_segment_register(collision_args, ctx)
            @test result == 1

            rows_after_no_force = create_connection(ctx.db_path) do conn
                fetch_segment_registration(conn)
            end
            @test rows_after_no_force == original_rows

            # Even with --force, multi-axis fails
            collision_args["force"] = true
            result = @test_logs (:error,) Lunk.run_segment_register(collision_args, ctx)
            @test result == 1

            rows_after_force = create_connection(ctx.db_path) do conn
                fetch_segment_registration(conn)
            end
            @test rows_after_force == original_rows
        end
    end

    # Efforts are purged when --force replaces a segment
    mktempdir() do dir
        ctx = make_context(dir)
        cd(dir) do
            path = abspath(dir * "/seg.osm")
            write(path, "test")
            args = Dict{String, Any}(
                "force" => false,
                "name" => "myseg",
                "path" => path
            )
            @test Lunk.run_segment_register(args, ctx) == 0

            # Get segment_id
            old_sid = create_connection(ctx.db_path) do conn
                row = fetch_segment_registration(conn, "myseg")
                row[:segment_id]
            end

            # Seed segment_efforts
            create_connection(ctx.db_path) do conn
                DBInterface.execute(
                    conn,
                    "INSERT INTO segment_efforts (activity_id, segment_id, elapsed_time_s, matched_at, matcher_version) VALUES (1, ?, 100.0, 1234, 20260607)",
                    [old_sid]
                )
            end

            # Force-register with same path but different content -> replaces
            write(path, "new-content")
            args["force"] = true
            @test Lunk.run_segment_register(args, ctx) == 0

            # Verify old efforts are gone
            create_connection(ctx.db_path) do conn
                result = DBInterface.execute(
                    conn,
                    "SELECT COUNT(*) AS n FROM segment_efforts WHERE segment_id = ?",
                    [old_sid]
                )
                @test only(NamedTuple(r) for r in result).n == 0
            end
        end
    end
end

@testset "run_segment_match" begin
    # Returns error on changed segment fingerprint
    mktempdir() do dir
        ctx = make_context(dir)
        cd(dir) do
            segment_path = dir * "/segment.osm"
            create_connection(ctx.db_path) do conn
                # Fake fingerprint ensures there will be a mismatch
                DBInterface.execute(
                    conn,
                    """
                    INSERT INTO segments (
                        name,
                        definition_fingerprint,
                        definition_path
                    ) VALUES (
                        "segment",
                        "fake-fingerprint",
                        ?
                    )
                    """,
                    [segment_path]
                )
                write(segment_path, "test")
                let args::Dict{String, Any} = Dict(
                        "name" => "segment",
                        "sport" => nothing
                    )
                    result = @test_logs (:error,) Lunk.run_segment_match(args, ctx)
                    @test result == 1
                end
            end
        end
    end
end

@testset "run_command segment show" begin
    @test_skip "stub: show segment leaderboard"
end
