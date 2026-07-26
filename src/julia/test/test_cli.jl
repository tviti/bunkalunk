using Test
using SQLite
using Lunk
using Logging
using Dates

include("fixtures.jl")

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

@testset "run_segment_subcommand dispatches subcommands" begin
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
            @test Lunk.run_segment_subcommand(args, ctx, subcommand_map) == 0
            @test called[] == "list"
        end
    end

    @testset "No command throws" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict("%COMMAND%" => nothing)
            subcommand_map = Lunk.CommandMap()
            @test_throws ArgumentError Lunk.run_segment_subcommand(args, ctx, subcommand_map)
        end
    end

    @testset "Unknown subcommand throws" begin
        with_tempdir_context() do ctx, dir
            args = Dict("%COMMAND%" => "bogus", "bogus" => Dict())
            subcommand_map = Lunk.CommandMap()
            @test_throws ArgumentError Lunk.run_segment_subcommand(args, ctx, subcommand_map)
        end
    end
end

@testset "run_activity_subcommand dispatches subcommands" begin
    @testset "Dispatches subcommands" begin
        with_tempdir_context() do ctx, dir
            called = Ref("")
            subcommand_map = Lunk.CommandMap(
                "export" => (x, y) -> begin
                    called[] = "export"; return 0
                end,
            )
            args = Dict("%COMMAND%" => "export", "export" => Dict())
            @test Lunk.run_activity_subcommand(args, ctx, subcommand_map) == 0
            @test called[] == "export"
        end
    end

    @testset "No command throws" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict("%COMMAND%" => nothing)
            subcommand_map = Lunk.CommandMap()
            @test_throws ArgumentError Lunk.run_activity_subcommand(args, ctx, subcommand_map)
        end
    end

    @testset "Unknown subcommand throws" begin
        with_tempdir_context() do ctx, dir
            args = Dict("%COMMAND%" => "bogus", "bogus" => Dict())
            subcommand_map = Lunk.CommandMap()
            @test_throws ArgumentError Lunk.run_activity_subcommand(args, ctx, subcommand_map)
        end
    end
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

    @testset "uses name from segment file when requested" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict(
                "force" => false,
                "name" => nothing,
                "path" => dir * "/segment.osm"
            )
            write_minimal_osm(args["path"]; name = "segment")
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

    @testset "fails when unable to determine segment name" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict(
                "force" => false,
                "name" => nothing,
                "path" => dir * "/segment.osm"
            )
            write_minimal_osm(args["path"]; name = nothing)
            result = @test_logs (:warn,) (:error,) Lunk.run_segment_register(args, ctx)
            @test result == 1
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
                insert_segment!(
                    conn,
                    "segment",
                    segment_path,
                    fingerprint,
                    make_dummy_segment()
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
                    insert_dummy_activity!(conn, "fingerprint")
                    DBInterface.execute(
                        conn,
                        """
                        INSERT INTO segment_efforts (
                            activity_id,
                            segment_id,
                            elapsed_time_s,
                            matched_at, 
                            matcher_version,
                            idx_start,
                            idx_end
                        ) VALUES (1, ?, 100.0, 1234, $matcher_version, 1, 2)
                        """,
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
                    insert_dummy_activity!(conn, "fingerprint")
                    DBInterface.execute(
                        conn,
                        """
                        INSERT INTO segment_efforts (
                            activity_id,
                            segment_id, 
                            elapsed_time_s,
                            matched_at,
                            matcher_version,
                            idx_start,
                            idx_end
                            ) VALUES (1, ?, 100.0, 1234, $matcher_version, 1, 2)
                        """,
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
    @testset "Happy path with no activities" begin
        with_tempdir_context() do ctx, dir
            segment_path = joinpath(dir, "segment.osm")
            write_minimal_osm(segment_path)
            fingerprint = open(segment_path, "r") do f
                compute_fingerprint(f)
            end
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                insert_segment!(
                    conn,
                    "segment",
                    abspath(segment_path),
                    fingerprint,
                    make_dummy_segment()
                )
            end

            args = Dict{String, Any}(
                "name" => "segment",
                "export" => nothing,
            )

            @test Lunk.run_segment_match(args, ctx) == 0
        end
    end

    @testset "Writes export files with no activities" begin
        with_tempdir_context() do ctx, dir
            segment_path = joinpath(dir, "segment.osm")
            export_path = joinpath(dir, "out.csv")
            write_minimal_osm(segment_path)
            fingerprint = open(segment_path, "r") do f
                compute_fingerprint(f)
            end
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                insert_segment!(
                    conn,
                    "segment",
                    abspath(segment_path),
                    fingerprint,
                    make_dummy_segment()
                )
            end

            args = Dict{String, Any}(
                "name" => "segment",
                "export" => export_path,
            )

            @test Lunk.run_segment_match(args, ctx) == 0
            @test isfile(export_path)
            @test isfile(joinpath(dir, "out.csvt"))
        end
    end

    @testset "Returns error on export write failure after saving efforts" begin
        with_tempdir_context() do ctx, dir
            segment_path = joinpath(dir, "segment.osm")
            export_path = joinpath(dir, "missing", "out.csv")
            write_minimal_osm(segment_path)
            fingerprint = open(segment_path, "r") do f
                compute_fingerprint(f)
            end
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                insert_segment!(
                    conn,
                    "segment",
                    abspath(segment_path),
                    fingerprint,
                    make_dummy_segment()
                )
            end

            args = Dict{String, Any}(
                "name" => "segment",
                "export" => export_path,
            )

            result = @test_logs (:error,) Lunk.run_segment_match(args, ctx)
            @test result == 1
            @test !isfile(export_path)
        end
    end

    @testset "Returns error on non-csv export path extension" begin
        with_tempdir_context() do ctx, dir
            args::Dict{String, Any} = Dict(
                "name" => "segment",
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
                insert_segment!(
                    conn,
                    "segment",
                    segment_path,
                    "fake-fingerprint",
                    make_dummy_segment()
                )
            end
            write(segment_path, "test")
            args::Dict{String, Any} = Dict(
                "name" => "segment",
                "export" => nothing
            )
            result = @test_logs (:error,) Lunk.run_segment_match(args, ctx)
            @test result == 1
        end
    end
end

function make_match_result(
        activity_id::Int64,
        segment_time::Real,
        matched_at::Int64
    )::MatchResult
    return MatchResult(
        DateTime(2026, 2, 6, 4, 30),
        activity_id,
        Float64(segment_time),
        matched_at,
        [[0.0, 0.0], [1.0, 1.0]],
        [10.0, 20.0],
        1,
        2
    )
end

@testset "segment_match_transaction!" begin
    @testset "Handles empty match_results with debug logging enabled" begin
        logger = TestLogger(min_level = Logging.Debug, catch_exceptions = false)

        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do conn
                with_logger(logger) do
                    result = Lunk.segment_match_transaction!(
                        conn,
                        1,
                        MatchResult[],
                        nothing,
                    )
                    @test result === nothing
                end
            end
        end
    end

    @testset "Records multiple efforts from multi-lap activity" begin
        # Two matches for the same activity should persist two efforts
        with_tempdir_context() do ctx, dir
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                seed_segments_table!(conn)
                insert_dummy_activity!(conn, "fingerprint-1")

                match_results = [
                    make_match_result(1, 20.0, 1000),
                    make_match_result(1, 21.5, 1001),
                ]

                result = Lunk.segment_match_transaction!(conn, 1, match_results, nothing)
                @test result === nothing

                efforts = fetch_segment_efforts_by_name(conn, "c")
                @test length(efforts) == 2
                @test efforts[1][:activity_id] == 1
                @test efforts[1][:elapsed_time_s] == 20.0
                @test efforts[1][:matched_at] == 1000
                @test efforts[2][:activity_id] == 1
                @test efforts[2][:elapsed_time_s] == 21.5
                @test efforts[2][:matched_at] == 1001
            end
        end
    end
    @testset "Removes pre-existing efforts" begin
        with_tempdir_context() do ctx, dir
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                seed_segments_table!(conn)
                insert_dummy_activity!(conn, "fingerprint-1")
                DBInterface.execute(
                    conn,
                    """
                    INSERT INTO segment_efforts (
                        activity_id,
                        segment_id,
                        elapsed_time_s,
                        matched_at,
                        matcher_version,
                        idx_start,
                        idx_end
                    ) VALUES (1, 1, 99.9, 9999, 20260101, 1, 2)
                    """
                )

                Lunk.segment_match_transaction!(
                    conn,
                    1,
                    [make_match_result(1, 20.0, 1000)],
                    nothing,
                )

                efforts = fetch_segment_efforts_by_name(conn, "c")
                @test length(efforts) == 1
                @test efforts[1][:activity_id] == 1
                @test efforts[1][:elapsed_time_s] == 20.0
                @test efforts[1][:matched_at] == 1000
            end
        end
    end
    @testset "Preserves efforts for activities not in match_results" begin
        with_tempdir_context() do ctx, dir
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                seed_segments_table!(conn)
                insert_dummy_activity!(conn, "fingerprint-1")
                insert_dummy_activity!(conn, "fingerprint-2")
                DBInterface.execute(
                    conn,
                    """
                    INSERT INTO segment_efforts (
                        activity_id, segment_id, elapsed_time_s,
                        matched_at, matcher_version,
                        idx_start, idx_end
                    ) VALUES
                        (1, 1, 99.9, 9999, 20260101, 1, 2),
                        (2, 1, 88.8, 8888, 20260101, 3, 4)
                    """
                )

                Lunk.segment_match_transaction!(
                    conn,
                    1,
                    [make_match_result(1, 20.0, 1000)],
                    nothing,
                )

                efforts = fetch_segment_efforts_by_name(conn, "c")
                @test length(efforts) == 2
                @test efforts[1][:activity_id] == 1
                @test efforts[1][:elapsed_time_s] == 20.0
                @test efforts[2][:activity_id] == 2
                @test efforts[2][:elapsed_time_s] == 88.8
            end
        end
    end
    @testset "Preserves efforts for the same activity under a different segment" begin
        with_tempdir_context() do ctx, dir
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                seed_segments_table!(conn)
                insert_dummy_activity!(conn, "fingerprint-1")
                DBInterface.execute(
                    conn,
                    """
                    INSERT INTO segment_efforts (
                        activity_id, segment_id, elapsed_time_s,
                        matched_at, matcher_version,
                        idx_start, idx_end
                    ) VALUES (1, 2, 99.9, 9999, 20260101, 1, 2)
                    """
                )

                Lunk.segment_match_transaction!(
                    conn,
                    1,
                    [make_match_result(1, 20.0, 1000)],
                    nothing,
                )

                efforts_c = fetch_segment_efforts_by_name(conn, "c")
                @test length(efforts_c) == 1
                @test efforts_c[1][:activity_id] == 1
                @test efforts_c[1][:elapsed_time_s] == 20.0

                efforts_b = fetch_segment_efforts_by_name(conn, "b")
                @test length(efforts_b) == 1
                @test efforts_b[1][:activity_id] == 1
                @test efforts_b[1][:elapsed_time_s] == 99.9
            end
        end
    end
    @testset "Handles multiple distinct activity_ids in one call" begin
        with_tempdir_context() do ctx, dir
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                seed_segments_table!(conn)
                insert_dummy_activity!(conn, "fingerprint-1")
                insert_dummy_activity!(conn, "fingerprint-2")
                DBInterface.execute(
                    conn,
                    """
                    INSERT INTO segment_efforts (
                        activity_id, segment_id, elapsed_time_s,
                        matched_at, matcher_version,
                        idx_start, idx_end
                    ) VALUES
                        (1, 1, 99.9, 9999, 20260101, 1, 2),
                        (2, 1, 88.8, 8888, 20260101, 3, 4)
                    """
                )

                Lunk.segment_match_transaction!(
                    conn,
                    1,
                    [
                        make_match_result(1, 20.0, 1000),
                        make_match_result(2, 15.0, 1001),
                    ],
                    nothing,
                )

                efforts = fetch_segment_efforts_by_name(conn, "c")
                @test length(efforts) == 2
                @test efforts[1][:activity_id] == 2
                @test efforts[1][:elapsed_time_s] == 15.0
                @test efforts[1][:matched_at] == 1001
                @test efforts[2][:activity_id] == 1
                @test efforts[2][:elapsed_time_s] == 20.0
                @test efforts[2][:matched_at] == 1000
            end
        end
    end
end

@testset "segment_remove" begin
    @testset "happy path" begin
        with_tempdir_context() do ctx, dir
            before = create_connection!(ctx.db_path) do db
                seed_segment_efforts_table!(db)
                fetch_segment_efforts_by_name(db, "c")
            end
            @test length(before) > 0
            args = Dict{String, Any}(
                "name" => "c"
            )
            result = @test_logs (:info,) Lunk.run_segment_remove(args, ctx)
            after, registration = create_connection!(ctx.db_path) do db
                (
                    fetch_segment_efforts_by_name(db, "c"),
                    fetch_segment_registration_by_name(db, "c"),
                )
            end
            @test length(after) == 0
            @test registration === nothing
        end
    end
end
