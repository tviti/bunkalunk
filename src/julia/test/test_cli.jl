using Test
using SQLite
using Lunk
using Logging


function make_context(dir::String; io::IO = IOBuffer())
    db_path = dir * "/db.sqlite3"
    activity_store_path = dir
    verbose = false
    return Lunk.Context(db_path, activity_store_path, verbose, io)
end

function with_tempdir_context(f::Function; io::IO = IOBuffer())
    return mktempdir() do dir
        cd(dir) do
            ctx = make_context(dir; io = io)
            f(ctx, dir)
        end
    end
end

@testset "run_command" begin
    @testset "Happy path" begin
        with_tempdir_context() do ctx, dir
            args = Dict(
                "%COMMAND%" => "segment",
                "segment" => Dict()
            )
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
    end

    @testset "Unknown command throws" begin
        with_tempdir_context() do ctx, dir
            args = Dict(
                "%COMMAND%" => "not-segment",
                "not-segment" => Dict()
            )
            command_map = Lunk.CommandMap(
                "segment" => (x, y) -> begin
                    return "fake result"
                end
            )
            @test_throws ArgumentError Lunk.run_command(args, ctx, command_map)
        end
    end

    @testset "No command throws" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict(
                "%COMMAND%" => nothing
            )
            command_map = Lunk.CommandMap("segment" => (x, y) -> return)
            @test_throws ArgumentError Lunk.run_command(args, ctx, command_map)
        end
    end
end

@testset "run_segment_command dispatches subcommands" begin
    @testset "Dispatches subcommands" begin
        with_tempdir_context() do ctx, dir
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
    end

    @testset "No command throws" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict("%COMMAND%" => nothing)
            subcommand_map = Lunk.CommandMap()
            @test_throws ArgumentError Lunk.run_segment_command(args, ctx, subcommand_map)
        end
    end

    @testset "Unknown subcommand throws" begin
        with_tempdir_context() do ctx, dir
            args = Dict("%COMMAND%" => "bogus", "bogus" => Dict())
            subcommand_map = Lunk.CommandMap()
            @test_throws ArgumentError Lunk.run_segment_command(args, ctx, subcommand_map)
        end
    end
end

function write_minimal_osm(path; name = "segment")
    # minimal valid file: one way, N nodes, nd refs match, name tag present
    # changing the name kwarg is an easy way to change the file contents (and
    # hence change the fingerprint)
    xml = """
        <osm>
            <node id="1" visible="true" lat="1.5" lon="2.25" />
            <node id="2" visible="true" lat="1.6" lon="2.35" />
            <way id="1" visible="true">
                    <nd ref="1" />
                    <nd ref="2" />
                    <tag k="name" v="$name" />
            </way>
        </osm> 
    """
    return write(path, xml)
end

@testset "run_segment_register" begin
    @testset "Happy path" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict(
                "force" => false,
                "name" => "segment",
                "path" => dir * "/segment.osm"
            )
            write_minimal_osm(args["path"])
            fingerprint = open(args["path"], "r") do f
                compute_fingerprint(f)
            end

            @test Lunk.run_segment_register(args, ctx) == 0

            row = create_connection!(ctx.db_path) do conn
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
    end

    @testset "run_segment_register always saves an abspath" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict(
                "force" => false,
                "name" => "segment",
                "path" => "./segment.osm"
            )
            write_minimal_osm(args["path"])
            @test Lunk.run_segment_register(args, ctx) == 0

            row = create_connection!(ctx.db_path) do conn
                result = DBInterface.execute(
                    conn,
                    "SELECT * FROM segments WHERE name = \"segment\""
                )
                return only(NamedTuple(r) for r in result)
            end

            @test isabspath(row[:definition_path])
        end
    end

    @testset "Exit on decode failure" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict(
                "force" => false,
                "name" => "segment",
                "path" => dir * "/segment.osm"
            )
            write(args["path"], "invalid-segment")
            result = @test_logs (:error,) Lunk.run_segment_register(args, ctx)
            @test result == 1
        end
    end

    @testset "run_segment_register collisions" begin
        with_tempdir_context() do ctx, dir
            segment_path = abspath(dir * "/segment.osm")
            other_path = abspath(dir * "/other.osm")
            write(segment_path, "test")
            fingerprint = open(segment_path, "r") do f
                compute_fingerprint(f)
            end
            create_connection!(ctx.db_path) do conn
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

            @testset "Path collision: same path, new name, new content" begin
                write_minimal_osm(segment_path, name = "new-name")
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
            end

            @testset "Name collision: same name, new path, new content" begin
                write_minimal_osm(other_path, name = "other-name")
                let args = Dict{String, Any}(
                        "force" => false,
                        "name" => "new-segment",
                        "path" => other_path
                    )
                    result = @test_logs (:error,) Lunk.run_segment_register(args, ctx)
                    @test result == 1
                    args["force"] = true
                    @test Lunk.run_segment_register(args, ctx) == 0
                end
            end

            @testset "Fingerprint collision: same content, new name, new path" begin
                let fp_path = abspath(dir * "/fp.osm")
                    write_minimal_osm(fp_path, name = "other-name")
                    fp = open(fp_path, "r") do f
                        compute_fingerprint(f)
                    end
                    create_connection!(ctx.db_path) do conn
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

        @testset "Exact match: same name, path, content -> no-op exit 0" begin
            with_tempdir_context() do ctx, dir
                path = abspath(dir * "/seg.osm")
                write_minimal_osm(path, name = "myseg")
                args = Dict{String, Any}(
                    "force" => false,
                    "name" => "myseg",
                    "path" => path
                )
                @test Lunk.run_segment_register(args, ctx) == 0

                old_sid = create_connection!(ctx.db_path) do conn
                    row = fetch_segment_registration(conn, "myseg")
                    row[:segment_id]
                end
                create_connection!(ctx.db_path) do conn
                    DBInterface.execute(
                        conn,
                        "INSERT INTO segment_efforts (activity_id, segment_id, elapsed_time_s, matched_at, matcher_version) VALUES (1, ?, 100.0, 1234, 20260607)",
                        [old_sid]
                    )
                end

                args = Dict{String, Any}(
                    "force" => false,
                    "name" => "myseg",
                    "path" => path
                )
                result = @test_logs (:info,) Lunk.run_segment_register(args, ctx)
                @test result == 0
                args["force"] = true
                result = @test_logs (:info,) Lunk.run_segment_register(args, ctx)
                @test result == 0

                create_connection!(ctx.db_path) do conn
                    result = DBInterface.execute(
                        conn,
                        "SELECT COUNT(*) AS n FROM segment_efforts WHERE segment_id = ?",
                        [old_sid]
                    )
                    @test only(NamedTuple(r) for r in result).n == 1
                end
            end
        end

        @testset "Multi-axis collision: name matches one row, path matches another -> always exit 1, even with --force" begin
            with_tempdir_context() do ctx, dir
                path_a = abspath(dir * "/a.osm")
                path_b = abspath(dir * "/b.osm")
                write_minimal_osm(path_a, name = "segment-a")
                write_minimal_osm(path_b, name = "segment-b")

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

                original_rows = create_connection!(ctx.db_path) do conn
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

                rows_after_no_force = create_connection!(ctx.db_path) do conn
                    fetch_segment_registration(conn)
                end
                @test rows_after_no_force == original_rows

                collision_args["force"] = true
                result = @test_logs (:error,) Lunk.run_segment_register(collision_args, ctx)
                @test result == 1

                rows_after_force = create_connection!(ctx.db_path) do conn
                    fetch_segment_registration(conn)
                end
                @test rows_after_force == original_rows
            end
        end

        @testset "Efforts are purged when --force replaces a segment" begin
            with_tempdir_context() do ctx, dir
                path = abspath(dir * "/seg.osm")
                write_minimal_osm(path, name = "myseg")
                args = Dict{String, Any}(
                    "force" => false,
                    "name" => "myseg",
                    "path" => path
                )
                @test Lunk.run_segment_register(args, ctx) == 0

                old_sid = create_connection!(ctx.db_path) do conn
                    row = fetch_segment_registration(conn, "myseg")
                    row[:segment_id]
                end

                create_connection!(ctx.db_path) do conn
                    DBInterface.execute(
                        conn,
                        "INSERT INTO segment_efforts (activity_id, segment_id, elapsed_time_s, matched_at, matcher_version) VALUES (1, ?, 100.0, 1234, 20260607)",
                        [old_sid]
                    )
                end

                write_minimal_osm(path, name = "new-content")
                args["force"] = true
                @test Lunk.run_segment_register(args, ctx) == 0

                create_connection!(ctx.db_path) do conn
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
end

@testset "run_segment_match" begin
    @testset "Returns error on non-csv export path extension" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict(
                "name" => "segment",
                "sport" => nothing,
                "export" => joinpath(dir, ".notcsv")
            )
            result = @test_logs (:error,) Lunk.run_segment_match(args, ctx)
            @test result == 1
        end
    end

    @testset "Returns error on changed segment fingerprint" begin
        with_tempdir_context() do ctx, dir
            segment_path = dir * "/segment.osm"
            create_connection!(ctx.db_path) do conn
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
            end
            write(segment_path, "test")
            args::Dict{String, Any} = Dict(
                "name" => "segment",
                "sport" => nothing,
                "export" => nothing
            )
            result = @test_logs (:error,) Lunk.run_segment_match(args, ctx)
            @test result == 1
        end
    end
end

@testset "run_command segment show" begin
    @test_skip "stub: show segment leaderboard"
end
