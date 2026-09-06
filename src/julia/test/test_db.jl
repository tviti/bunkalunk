using Test
using Lunk
using SQLite
using Dates

include("fixtures.jl")

function insert_source_file(conn::SQLite.DB, source_file::Dict)::Nothing
    DBInterface.execute(
        conn,
        """
        INSERT INTO source_files (
               source_path,
               content_fingerprint,
               decode_state,
               decode_error
        ) VALUES (
               :source_path,
               :content_fingerprint,
               :decode_state,
               :decode_error
        )
        """,
        source_file
    )
    return
end

function seed_source_files_table!(conn::SQLite.DB)::Nothing
    insert_source_file(
        conn, Dict(
            :source_path => "a/fake/path.fit",
            :content_fingerprint => "123",
            :decode_state => "pending",
            :decode_error => nothing
        )
    )
    insert_source_file(
        conn, Dict(
            :source_path => "a/nother/fake/path.fit",
            :content_fingerprint => "456",
            :decode_state => "success",
            :decode_error => nothing
        )
    )
    return
end

function seed_activities_table!(conn::SQLite.DB)::Nothing
    insert_activity!(
        conn, Dict(
            :start_time => 1770267600.0, # 2026-02-05T05:00:00
            :source_fingerprint => "123",
            :ride_tag => nothing,
            :sport => "cycling",
            :cache_version => 20260101,
            :x_min => 0.0,
            :x_max => 2.0,
            :y_min => 0.0,
            :y_max => 1.0
        )
    )
    insert_activity!(
        conn, Dict(
            :start_time => 1770354000.0, # 2026-02-06T05:00:00
            :source_fingerprint => "456",
            :ride_tag => nothing,
            :sport => "basket-weaving",
            :cache_version => 20260101,
            :x_min => 3.0,
            :x_max => 6.0,
            :y_min => 0.0,
            :y_max => 2.0
        )
    )
    insert_activity!(
        conn, Dict(
            :start_time => 1770390000.0, # 2026-02-06T15:00:00
            :source_fingerprint => "789",
            :ride_tag => nothing,
            :sport => "cycling",
            :cache_version => 20260101,
            :x_min => 0.0,
            :x_max => 4.0,
            :y_min => 3.0,
            :y_max => 5.0
        )
    )
    insert_activity!(
        conn, Dict(
            :start_time => 1770508800.0, # 2026-02-08T00:00:00
            :source_fingerprint => "abc",
            :ride_tag => nothing,
            :sport => "cycling",
            :cache_version => 20260101,
            :x_min => 5.0,
            :x_max => 10.0,
            :y_min => 3.0,
            :y_max => 4.0
        )
    )
    insert_activity!(
        conn, Dict(
            :start_time => 1772690400.0, # 2026-03-05T06:00:00
            :source_fingerprint => "123-copy",
            :ride_tag => nothing,
            :sport => "cycling",
            :cache_version => 20260102,
            :x_min => 0.0,
            :x_max => 2.0,
            :y_min => 0.0,
            :y_max => 1.0
        )
    )
    return
end

function with_activities_db(f::Function)
    return mktempdir() do dir
        db_path = joinpath(dir, "db.sqlite3")
        create_bunk_tables!(db_path)
        create_connection!(db_path) do conn
            seed_activities_table!(conn)
            f(conn)
        end
    end
end

@testset "get_content_fingerprint" begin
    mktempdir() do dir
        db_path = joinpath(dir, "db.sqlite3")
        create_bunk_tables!(db_path)
        let conn = SQLite.DB(db_path)
            try
                seed_source_files_table!(conn)
                @test get_content_fingerprint(conn, "a/fake/path.fit") == "123"
            finally
                close(conn)
            end
        end
    end
end

@testset "select_by_start_date" begin
    @testset "Happy path" begin
        with_activities_db() do conn
            @test select_by_start_date(conn, "2026-02-05") == ["123"]
        end
    end

    @testset "multiple matches: two activities with start_time on the same date" begin
        with_activities_db() do conn
            @test select_by_start_date(conn, "2026-02-06") == ["456", "789"]
        end
    end

    @testset "upper boundary: exactly midnight opening the next day should be excluded" begin
        with_activities_db() do conn
            @test select_by_start_date(conn, "2026-02-07") == []
        end
    end

    @testset "sport filter that matches seed data — only cycling returned" begin
        with_activities_db() do conn
            @test select_by_start_date(conn, "2026-02-06", sport = "cycling") == ["789"]
        end
    end

    @testset "sport filter that matches no activities — empty result" begin
        with_activities_db() do conn
            @test select_by_start_date(conn, "2026-02-06", sport = "running") == []
        end
    end

    @testset "sport=nothing behaves identically to the no-sport overload" begin
        with_activities_db() do conn
            @test select_by_start_date(conn, "2026-02-06", sport = nothing) == ["456", "789"]
        end
    end
end

@testset "select_by_time_range" begin
    @testset "Happy path" begin
        with_activities_db() do conn
            @test select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 5, 30)
            ) == ["456"]
        end
    end

    @testset "multiple matches: time range spanning more than one activity" begin
        with_activities_db() do conn
            @test select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 15, 30)
            ) == ["456", "789"]
        end
    end

    @testset "upper boundary: start_time exactly equal to t1 is excluded (range is >= t0, < t1)" begin
        with_activities_db() do conn
            @test select_by_time_range(
                conn,
                DateTime(2026, 2, 5, 5, 00),
                DateTime(2026, 2, 6, 5, 00)
            ) == ["123"]
        end
    end

    @testset "sport filter that matches seed data — only cycling returned" begin
        with_activities_db() do conn
            @test select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 15, 30),
                sport = "cycling"
            ) == ["789"]
        end
    end

    @testset "sport filter that matches no activities in range — empty result" begin
        with_activities_db() do conn
            @test select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 15, 30),
                sport = "running"
            ) == []
        end
    end

    @testset "sport=nothing behaves identically to the no-sport overload" begin
        with_activities_db() do conn
            @test select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 15, 30),
                sport = nothing
            ) == ["456", "789"]
        end
    end
end

@testset "select_by_id" begin
    @testset "input roundtrip" begin
        with_activities_db() do conn
            @test select_by_id(conn, 3) == "789"
        end
    end

    @testset "raises on scalar input with no match" begin
        with_activities_db() do conn
            @test_throws ArgumentError select_by_id(conn, 99) === nothing
        end
    end
end

@testset "create_connection" begin
    @testset "verifies table schemas created by create_connection" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                cols = DBInterface.execute(db, "PRAGMA table_info(segments)")
                names = [row[:name] for row in cols]
                @test names == [
                    "segment_id",
                    "name",
                    "definition_fingerprint",
                    "definition_path",
                    "x_min",
                    "x_max",
                    "y_min",
                    "y_max",
                ]

                cols = DBInterface.execute(db, "PRAGMA table_info(segment_efforts)")
                names = [row[:name] for row in cols]
                @test names == [
                    "effort_id", "activity_id", "segment_id", "elapsed_time_s", "matched_at",
                    "matcher_version", "idx_start", "idx_end",
                ]
            end
        end
    end

    @testset "errors thrown inside the do-block should propagate out" begin
        with_tmp_bunk_db!() do _, db_path
            @test_throws ErrorException create_connection!(db_path) do _
                error("test error")
            end
        end
    end

    @testset "connection is closed even when the do-block raises an error" begin
        with_tmp_bunk_db!() do dir, db_path
            ref = Ref{SQLite.DB}()
            try
                create_connection!(db_path) do db
                    ref[] = db
                    error("test error")
                end
            catch
            end
            @test !SQLite.isopen(ref[])
        end
    end
end

@testset "insert_segment" begin
    @testset "Happy path" begin
        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do db
                insert_segment!(
                    db,
                    "segment",
                    "path/to/segment",
                    "fingerprint",
                    make_dummy_segment()
                )
                result = DBInterface.execute(
                    db,
                    "SELECT * FROM segments WHERE name = ?",
                    ["segment"]
                )
                row = only(NamedTuple(row) for row in result)
                @test row[:name] == "segment"
                @test row[:definition_path] == "path/to/segment"
                @test row[:definition_fingerprint] == "fingerprint"
            end
        end
    end

    @testset "Name conflict throws SQLiteException" begin
        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do db
                insert_segment!(
                    db,
                    "segment",
                    "path/to/segment",
                    "fingerprint",
                    make_dummy_segment()
                )
                @test_throws SQLiteException begin
                    insert_segment!(
                        db,
                        "segment",
                        "path/to/segment",
                        "new-fingerprint",
                        make_dummy_segment()
                    )
                end
            end
        end
    end

    @testset "Path conflict throws SQLiteException" begin
        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do db
                insert_segment!(
                    db,
                    "segment",
                    "path/to/segment",
                    "fingerprint",
                    make_dummy_segment()
                )
                @test_throws SQLiteException begin
                    insert_segment!(
                        db,
                        "new-segment",
                        "path/to/segment",
                        "new-fingerprint",
                        make_dummy_segment()
                    )
                end
            end
        end
    end

    @testset "Fingerprint conflict throws SQLiteException" begin
        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do db
                insert_segment!(
                    db,
                    "segment",
                    "path/to/segment",
                    "fingerprint",
                    make_dummy_segment()
                )
                @test_throws SQLiteException begin
                    insert_segment!(
                        db,
                        "new-segment",
                        "new-path/to/segment",
                        "fingerprint",
                        make_dummy_segment()
                    )
                end

            end
        end
    end

    @testset "Conflicts must not partially update the original row" begin
        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do db
                insert_segment!(
                    db,
                    "segment",
                    "path/to/segment",
                    "fingerprint",
                    make_dummy_segment()
                )
                @test_throws SQLiteException begin
                    insert_segment!(
                        db,
                        "new-segment",
                        "new-path/to/segment",
                        "fingerprint",
                        make_dummy_segment()
                    )
                end

                result = DBInterface.execute(
                    db,
                    "SELECT * FROM segments WHERE name = ?",
                    ["segment"]
                )
                row = only(NamedTuple(row) for row in result)
                @test row[:name] == "segment"
                @test row[:definition_path] == "path/to/segment"
                @test row[:definition_fingerprint] == "fingerprint"
            end
        end
    end
end

@testset "insert_segment_effort" begin
    @testset "Happy path" begin
        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do db
                insert_dummy_activity!(db, "fingerprint")
                seed_segments_table!(db)
                insert_segment_effort!(db, 1, 3, 123.456, 13, 123456, 1, 2)
                result = DBInterface.execute(
                    db,
                    "SELECT * FROM segment_efforts WHERE segment_id = ?",
                    [3]
                )
                segment_efforts_row = only(NamedTuple(r) for r in result)
                @test segment_efforts_row[:activity_id] == 1
                @test segment_efforts_row[:segment_id] == 3
                @test segment_efforts_row[:elapsed_time_s] == 123.456
                @test segment_efforts_row[:matched_at] == 13
                @test segment_efforts_row[:matcher_version] == 123456
            end
        end
    end

    @testset "Repeating the same match should add a duplicate" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                insert_dummy_activity!(db, "fingerprint")
                seed_segments_table!(db)
                insert_segment_effort!(db, 1, 3, 123.456, 13, 123456, 1, 2)
                insert_segment_effort!(db, 1, 3, 222.0, 14, 654321, 3, 4)
                result = DBInterface.execute(
                    db,
                    """
                        SELECT * FROM segment_efforts
                        WHERE activity_id = ? AND segment_id = ?
                    """,
                    [1, 3]
                )
                results = [NamedTuple(r) for r in result]
                @test length(results) == 2
                @test results[1][:elapsed_time_s] == 123.456
                @test results[1][:matched_at] == 13
                @test results[1][:matcher_version] == 123456
                @test results[2][:elapsed_time_s] == 222.0
                @test results[2][:matched_at] == 14
                @test results[2][:matcher_version] == 654321
            end
        end
    end
end

@testset "select_all" begin
    @testset "No sport returns all rows" begin
        with_activities_db() do db
            @test select_all(db) == [(1, "123"), (2, "456"), (3, "789"), (4, "abc"), (5, "123-copy")]
        end
    end

    @testset "Selects only requested sport" begin
        with_activities_db() do db
            @test select_all(db, sport = "cycling") == [(1, "123"), (3, "789"), (4, "abc"), (5, "123-copy")]
        end
    end

    @testset "No matches yields empty result" begin
        with_activities_db() do db
            @test select_all(db, sport = "running") == []
        end
    end

    @testset "sport = nothing behaves same as no sport" begin
        with_activities_db() do db
            @test select_all(db, sport = nothing) == [(1, "123"), (2, "456"), (3, "789"), (4, "abc"), (5, "123-copy")]
        end
    end
end

@testset "select_overlapping" begin
    @testset "Complete overlap" begin
        with_activities_db() do db
            rows = select_overlapping(db, 0.5, 0.2, 1.5, 0.8)
            @test rows == [(1, "123"), (5, "123-copy")]
        end
    end

    @testset "Partial overlap" begin
        with_activities_db() do db
            rows = select_overlapping(db, 5.5, 1.0, 7.0, 2.5)
            @test length(rows) == 1
            @test rows[1][2] == "456"
        end
    end

    @testset "No overlap" begin
        with_activities_db() do db
            rows = select_overlapping(db, 7.0, 5.0, 8.0, 6.0)
            @test length(rows) == 0
        end
    end

    @testset "only_unmatched_to excludes rows with a corresponding effort" begin
        with_activities_db() do db
            insert_segment!(
                db,
                "segment",
                "path/to/segment",
                "fingerprint",
                make_dummy_segment()
            )
            insert_segment_effort!(db, 5, 1, 123.456, 13, Lunk.MATCHER_VERSION, 1, 2)
            rows = select_overlapping(
                db, 0.5, 0.2, 1.5, 0.8; only_unmatched_to = 1
            )
            @test rows == [(1, "123")]
        end
    end

    @testset "only_unmatched_to includes stale efforts" begin
        with_activities_db() do db
            insert_segment!(
                db,
                "segment",
                "path/to/segment",
                "fingerprint",
                make_dummy_segment()
            )
            insert_segment_effort!(db, 5, 1, 123.456, 13, Lunk.MATCHER_VERSION - 1, 1, 2)
            rows = select_overlapping(
                db, 0.5, 0.2, 1.5, 0.8; only_unmatched_to = 1
            )
            @test rows == [(1, "123"), (5, "123-copy")]
        end
    end
end

@testset "select_segments_overlapping_activity" begin
    @testset "returns segment with full overlap" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                insert_dummy_activity!(db, "activity")
                insert_segment!(
                    db,
                    "contained",
                    "path/to/contained",
                    "fingerprint-contained",
                    Segment("contained", [0.2, 0.8], [0.2, 0.8])
                )

                registrations = Lunk.select_segments_overlapping_activity(db, 1)
                registration = only(registrations)

                @test registration[:segment_id] == 1
                @test registration[:name] == "contained"
                @test registration[:definition_path] == "path/to/contained"
                @test registration[:definition_fingerprint] == "fingerprint-contained"
                @test registration[:x_min] == 0.2
                @test registration[:x_max] == 0.8
                @test registration[:y_min] == 0.2
                @test registration[:y_max] == 0.8
            end
        end
    end

    @testset "returns segment with partial overlap" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                insert_dummy_activity!(db, "activity")
                insert_segment!(
                    db,
                    "partial",
                    "path/to/partial",
                    "fingerprint-partial",
                    Segment("partial", [0.2, 0.8], [0.8, 1.2])
                )

                registrations = Lunk.select_segments_overlapping_activity(db, 1)

                @test length(registrations) == 1
                @test only(registrations)[:name] == "partial"
            end
        end
    end

    @testset "no overlap returns empty array" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                insert_dummy_activity!(db, "activity")
                insert_segment!(
                    db,
                    "disjoint",
                    "path/to/disjoint",
                    "fingerprint-disjoint",
                    Segment("disjoint", [0.2, 0.8], [1.1, 1.2])
                )

                @test isempty(Lunk.select_segments_overlapping_activity(db, 1))
            end
        end
    end
end

@testset "fetch_segment_registration all" begin
    @testset "Returns all rows ordered by name" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                regs = fetch_segment_registration(db)
                @test regs[1][:name] == "c"
                @test regs[2][:name] == "b"
                @test regs[3][:name] == "a"
                @test regs[1][:definition_path] == "path/to/c"
                @test regs[2][:definition_path] == "path/to/b"
                @test regs[3][:definition_path] == "path/to/a"
                @test regs[1][:definition_fingerprint] == "fingerprint-c"
                @test regs[2][:definition_fingerprint] == "fingerprint-b"
                @test regs[3][:definition_fingerprint] == "fingerprint-a"
            end
        end
    end
end

@testset "fetch_segment_names" begin
    @testset "Happy path and and results ordered by name" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do conn
                seed_segments_table!(conn)
                names = fetch_segment_names(conn)
                @test names == ["a", "b", "c"]
            end
        end
    end
end

@testset "remove_segment" begin
    @testset "Removes the requested segment from segments" begin
        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                row = remove_segment!(db, "b")
                @test row[:name] == "b"
                @test fetch_segment_names(db) == ["a", "c"]
            end
        end
    end

    @testset "Unknown segment" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                @test remove_segment!(db, "nonexistent") === nothing
                @test fetch_segment_names(db) == ["a", "b", "c"]
            end
        end
    end
end

@testset "remove_segment_efforts" begin
    @testset "Removes the efforts for the given segment_id" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                rows = remove_segment_efforts!(db, 2)
                @test length(rows) == 2
                @test rows[1][:segment_id] == 2
                @test rows[2][:segment_id] == 2
                result = DBInterface.execute(
                    db, "SELECT * FROM segment_efforts ORDER BY effort_id"
                )
                rows = [NamedTuple(r) for r in result]
                @test length(rows) == 2
                @test rows[1][:segment_id] == 3
                @test rows[2][:segment_id] == 1
            end
        end
    end

    @testset "Does nothing for unknown segment_ids" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                rows = remove_segment_efforts!(db, 99999)
                @test rows == []
                result = DBInterface.execute(
                    db, "SELECT COUNT(*) AS n FROM segment_efforts"
                )
                @test only(NamedTuple(r) for r in result).n == 4
            end
        end
    end
end

@testset "remove_segment_efforts (segment_id, activity_id)" begin
    @testset "Removes only efforts matching both segment_id and activity_id" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                rows = remove_segment_efforts!(db, 2, 2)
                @test length(rows) == 1
                @test rows[1][:segment_id] == 2
                @test rows[1][:activity_id] == 2
                result = DBInterface.execute(
                    db, "SELECT * FROM segment_efforts ORDER BY effort_id"
                )
                rows = [NamedTuple(r) for r in result]
                @test length(rows) == 3
                @test rows[1][:activity_id] == 1
                @test rows[2][:activity_id] == 3
                @test rows[3][:activity_id] == 4
            end
        end
    end

    @testset "Does nothing for unknown activity_id" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                rows = remove_segment_efforts!(db, 2, 99999)
                @test rows == []
                result = DBInterface.execute(
                    db, "SELECT COUNT(*) AS n FROM segment_efforts"
                )
                @test only(NamedTuple(r) for r in result).n == 4
            end
        end
    end

    @testset "Does nothing for unknown segment_id" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                rows = remove_segment_efforts!(db, 99999, 1)
                @test rows == []
                result = DBInterface.execute(
                    db, "SELECT COUNT(*) AS n FROM segment_efforts"
                )
                @test only(NamedTuple(r) for r in result).n == 4
            end
        end
    end

    @testset "only_stale removes stale efforts and preserves current efforts" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                DBInterface.execute(
                    db,
                    """
                    INSERT INTO segment_efforts (
                        activity_id,
                        segment_id,
                        elapsed_time_s,
                        matched_at,
                        matcher_version,
                        idx_start,
                        idx_end
                    ) VALUES (2, 2, 99.9, 1238, $(Lunk.MATCHER_VERSION - 1), 9, 10)
                    """
                )

                rows = remove_segment_efforts!(db, 2, 2; only_stale = true)
                @test length(rows) == 1
                @test rows[1][:effort_id] == 5
                @test rows[1][:matcher_version] == Lunk.MATCHER_VERSION - 1

                remaining = DBInterface.execute(
                    db,
                    """
                    SELECT effort_id, matcher_version
                    FROM segment_efforts
                    WHERE segment_id = 2 AND activity_id = 2
                    """
                )
                remaining = [NamedTuple(row) for row in remaining]
                @test remaining == [(effort_id = 2, matcher_version = Lunk.MATCHER_VERSION)]
            end
        end
    end
end

@testset "fetch_segment_registration_by_name" begin
    @testset "Happy path" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                row = Lunk.fetch_segment_registration_by_name(db, "b")
                @test row !== nothing
                @test row[:name] == "b"
                @test row[:definition_fingerprint] == "fingerprint-b"
                @test row[:definition_path] == "path/to/b"
            end
        end
    end

    @testset "Missing segment returns nothing" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                @test Lunk.fetch_segment_registration_by_name(db, "nonexistent") === nothing
            end
        end
    end
end

@testset "fetch_segment_registration_by_fingerprint" begin
    @testset "Happy path" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                row = Lunk.fetch_segment_registration_by_fingerprint(db, "fingerprint-b")
                @test row !== nothing
                @test row[:name] == "b"
                @test row[:definition_fingerprint] == "fingerprint-b"
                @test row[:definition_path] == "path/to/b"
            end
        end
    end

    @testset "Missing fingerprint returns nothing" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                @test Lunk.fetch_segment_registration_by_fingerprint(db, "nonexistent-fp") === nothing
            end
        end
    end
end

@testset "fetch_segment_registration_by_path" begin
    @testset "Happy path" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                row = Lunk.fetch_segment_registration_by_path(db, "path/to/b")
                @test row !== nothing
                @test row[:name] == "b"
                @test row[:definition_fingerprint] == "fingerprint-b"
                @test row[:definition_path] == "path/to/b"
            end
        end
    end

    @testset "Missing path returns nothing" begin
        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                @test Lunk.fetch_segment_registration_by_path(db, "nonexistent/path") === nothing
            end
        end
    end
end

@testset "remove_segment by id" begin
    @testset "Happy path" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                @test length(fetch_segment_names(db)) == 3

                row = Lunk.remove_segment!(db, 2)
                @test row[:segment_id] == 2
                @test row[:name] == "b"
                @test fetch_segment_names(db) == ["a", "c"]
            end
        end
    end

    @testset "Silent no-op on missing segment_id" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segments_table!(db)
                @test Lunk.remove_segment!(db, 99999) === nothing
                @test fetch_segment_names(db) == ["a", "b", "c"]
            end
        end
    end
end

@testset "fetch_segment_efforts_by_pairing" begin
    @testset "roundtrip" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                efforts = fetch_segment_efforts_by_pairing(db, 2, 2)
                e = only(efforts)
                @test e[:effort_id] == 2
                @test e[:activity_id] == 2
                @test e[:segment_id] == 2
                @test e[:elapsed_time_s] == 101.1
                @test e[:matched_at] == 1235
                @test e[:matcher_version] == Lunk.MATCHER_VERSION
                @test e[:idx_start] == 3
                @test e[:idx_end] == 4
                @test e[:start_time] == 99.999
                @test e[:name] == "b"
                @test e[:sport] == "cycling"
            end
        end
    end

    @testset "no matches" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                @test fetch_segment_efforts_by_pairing(db, 99999, 99999) == []
            end
        end
    end
end

@testset "fetch_segment_efforts_by_name" begin
    @testset "roundtrip no sport filter" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                efforts = fetch_segment_efforts_by_name(db, "a")
                e = only(efforts)
                @test e[:effort_id] == 1
                @test e[:activity_id] == 1
                @test e[:segment_id] == 3
                @test e[:elapsed_time_s] == 100.0
                @test e[:matched_at] == 1234
                @test e[:matcher_version] == Lunk.MATCHER_VERSION
                @test e[:idx_start] == 1
                @test e[:idx_end] == 2
                @test e[:start_time] == 99.999
                @test e[:name] == "a"
                @test e[:sport] == "cycling"
            end
        end
    end

    @testset "roundtrip with sport filter" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                efforts = fetch_segment_efforts_by_name(db, "b"; sport = "basket-weaving")
                e = only(efforts)
                @test e[:effort_id] == 3
                @test e[:activity_id] == 3
                @test e[:segment_id] == 2
                @test e[:elapsed_time_s] == 102.2
                @test e[:matched_at] == 1236
                @test e[:matcher_version] == Lunk.MATCHER_VERSION
                @test e[:idx_start] == 5
                @test e[:idx_end] == 6
                @test e[:start_time] == 99.999
                @test e[:name] == "b"
                @test e[:sport] == "basket-weaving"
            end
        end
    end

    @testset "no matches" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                efforts = fetch_segment_efforts_by_name(db, "b"; sport = "unsporty")
                @test efforts == []
            end
        end
    end
end

@testset "fetch_segment_efforts_by_activity_id" begin
    function with_seeded_efforts_table(f::Function)
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)

                # Ensure activity 1 matches multiple segments
                insert_segment_effort!(db, 1, 1, 98.8, 1238, Lunk.MATCHER_VERSION, 9, 10)
                insert_segment_effort!(db, 1, 2, 99.9, 1239, Lunk.MATCHER_VERSION, 11, 12)

                # Activity matching nothing
                insert_dummy_activity!(db, "fingerprint-5")

                # Activity matching nothing, and with no sport
                insert_dummy_activity!(db, "fingerprint-6"; sport = nothing)
                insert_segment_effort!(db, 6, 1, 104.4, 1240, Lunk.MATCHER_VERSION, 13, 14)
                insert_dummy_activity!(db, "fingerprint-7"; sport = nothing)
                insert_segment_effort!(db, 7, 1, 105.5, 1241, Lunk.MATCHER_VERSION, 15, 16)

                f(db)
            end
        end
    end

    @testset "happy path" begin
        with_tmp_bunk_db!() do _, db_path
            create_connection!(db_path) do db
                seed_segment_efforts_table!(db)
                efforts = Lunk.fetch_segment_efforts_by_activity_id(db, 1)
                e = only(efforts)
                @test e[:effort_id] == 1
                @test e[:activity_id] == 1
                @test e[:segment_id] == 3
                @test e[:elapsed_time_s] == 100.0
                @test e[:matched_at] == 1234
                @test e[:matcher_version] == Lunk.MATCHER_VERSION
                @test e[:idx_start] == 1
                @test e[:idx_end] == 2
                @test e[:start_time] == 99.999
                @test e[:name] == "a"
                @test e[:sport] == "cycling"
            end
        end
    end

    @testset "returns efforts for all matched segments" begin
        with_seeded_efforts_table() do db
            activity_id = 1
            efforts = Lunk.fetch_segment_efforts_by_activity_id(db, activity_id)
            matched_segment_ids = unique([e[:segment_id] for e in efforts])
            @test matched_segment_ids == Int64[1, 2, 3]
            for segment_id in matched_segment_ids
                segment_efforts = filter((x) -> x[:segment_id] == segment_id, efforts)
                activity_ids = [e[:activity_id] for e in segment_efforts]
                @test activity_id in activity_ids
            end
        end
    end

    @testset "excludes activities matching segment but not sport" begin
        with_seeded_efforts_table() do db
            activity_id = 1
            excluded_activity_id = 3

            let results = DBInterface.execute(
                    db,
                    "SELECT sport FROM activities WHERE activity_id = ?;",
                    (excluded_activity_id,)
                )
                @test only([r[:sport] for r in results]) == "basket-weaving"
            end

            efforts = Lunk.fetch_segment_efforts_by_activity_id(db, activity_id)
            matched_segment_ids = unique([e[:segment_id] for e in efforts])
            @test matched_segment_ids == Int64[1, 2, 3]
            activity_ids = [e[:activity_id] for e in efforts]
            @test !(excluded_activity_id in activity_ids)
            @test all([e[:sport] for e in efforts] .== "cycling")
        end
    end

    @testset "returns empty list on activity_id with no matches" begin
        with_seeded_efforts_table() do db
            efforts = Lunk.fetch_segment_efforts_by_activity_id(db, 5)
            @test isempty(efforts)
        end
    end

    @testset "return value is ordered by segment_id, elapsed_time_s" begin
        with_seeded_efforts_table() do db
            expected = [(1, 98.8), (1, 103.3), (2, 99.9), (2, 101.1), (3, 100.0)]
            efforts = Lunk.fetch_segment_efforts_by_activity_id(db, 1)
            @test [(e[:segment_id], e[:elapsed_time_s]) for e in efforts] == expected
        end
    end

    @testset "returns empty list on nonexistent activity" begin
        with_seeded_efforts_table() do db
            efforts = Lunk.fetch_segment_efforts_by_activity_id(db, 100)
            @test isempty(efforts)
        end
    end

    @testset "null sport returns rows with null sport" begin
        with_seeded_efforts_table() do db
            efforts = Lunk.fetch_segment_efforts_by_activity_id(db, 6)
            @test length(efforts) == 2
            @test all(e[:segment_id] == 1 for e in efforts)
            @test all(e[:sport] === missing for e in efforts)
        end
    end
end
