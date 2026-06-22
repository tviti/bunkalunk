using Test
using Lunk
using SQLite
using Dates

include("fixtures.jl")

function create_bunk_tables!(conn::SQLite.DB)::Nothing
    DBInterface.execute(
        conn, """
        CREATE TABLE IF NOT EXISTS source_files (
            source_path TEXT PRIMARY KEY,
            content_fingerprint TEXT NOT NULL,
            decode_state TEXT,
            decode_error TEXT
        )
        """
    )
    create_activities_table!(conn)
    return
end

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

function insert_activity(conn::SQLite.DB, activity::Dict)::Nothing
    DBInterface.execute(
        conn,
        """
        INSERT INTO activities (
               start_time,
               source_fingerprint,
               ride_tag,
               sport,
               cache_version
        ) VALUES (
               :start_time,
               :source_fingerprint,
               :ride_tag,
               :sport,
               :cache_version
        )
        """,
        activity
    )
    return
end

function seed_activities_table!(conn::SQLite.DB)::Nothing
    insert_activity(
        conn, Dict(
            :start_time => 1770267600.0, # 2026-02-05T05:00:00
            :source_fingerprint => "123",
            :ride_tag => nothing,
            :sport => "cycling",
            :cache_version => 20260101
        )
    )
    insert_activity(
        conn, Dict(
            :start_time => 1770354000.0, # 2026-02-06T05:00:00
            :source_fingerprint => "456",
            :ride_tag => nothing,
            :sport => "basket-weaving",
            :cache_version => 20260101
        )
    )
    insert_activity(
        conn, Dict(
            :start_time => 1770390000.0, # 2026-02-06T15:00:00
            :source_fingerprint => "789",
            :ride_tag => nothing,
            :sport => "cycling",
            :cache_version => 20260101
        )
    )
    insert_activity(
        conn, Dict(
            :start_time => 1770508800.0, # 2026-02-08T00:00:00
            :source_fingerprint => "abc",
            :ride_tag => nothing,
            :sport => "cycling",
            :cache_version => 20260101
        )
    )
    return
end

function with_activities_db(f::Function)
    conn = SQLite.DB()
    return try
        create_bunk_tables!(conn)
        seed_activities_table!(conn)
        f(conn)
    finally
        close(conn)
    end
end

function seed_segments_table!(db::SQLite.DB)::Nothing
    DBInterface.execute(
        db,
        """
            INSERT INTO segments (name, definition_fingerprint, definition_path)
            VALUES
                ("c", "fingerprint-c", "path/to/c"),
                ("b", "fingerprint-b", "path/to/b"),
                ("a", "fingerprint-a", "path/to/a");
        """
    )
    return
end

function seed_segment_efforts_table!(db::SQLite.DB)::Nothing
    DBInterface.execute(
        db,
        """
            INSERT INTO segment_efforts (activity_id,
                                         segment_id,
                                         elapsed_time_s,
                                         matched_at,
                                         matcher_version)
            VALUES
                (1, 3, 100.0, 1234, 20260607),
                (2, 2, 101.1, 1235, 20260607),
                (100, 2, 102.2, 1236, 20260607),
                (110, 1, 103.3, 1237, 20260607);
        """
    )
    return
end

@testset "get_content_fingerprint" begin
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_source_files_table!(conn)
            @test get_content_fingerprint(conn, "a/fake/path.fit") == "123"
        finally
            close(conn)
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

@testset "create_connection" begin
    @testset "verifies table schemas created by create_connection" begin
        create_connection!(":memory:") do db
            cols = DBInterface.execute(db, "PRAGMA table_info(segments)")
            names = [row[:name] for row in cols]
            @test names == [
                "segment_id", "name", "definition_fingerprint", "definition_path",
            ]

            cols = DBInterface.execute(db, "PRAGMA table_info(segment_efforts)")
            names = [row[:name] for row in cols]
            @test names == [
                "effort_id", "activity_id", "segment_id", "elapsed_time_s", "matched_at",
                "matcher_version",
            ]
        end
    end

    @testset "errors thrown inside the do-block should propagate out" begin
        @test_throws ErrorException create_connection!(":memory:") do db
            error("test error")
        end
    end

    @testset "connection is closed even when the do-block raises an error" begin
        ref = Ref{SQLite.DB}()
        try
            create_connection!(":memory:") do db
                ref[] = db
                error("test error")
            end
        catch
        end
        @test !SQLite.isopen(ref[])
    end
end

@testset "insert_segment" begin
    @testset "Happy path" begin
        create_connection!(":memory:") do db
            insert_segment!(db, "segment", "path/to/segment", "fingerprint")
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

    @testset "Name conflict throws SQLiteException" begin
        create_connection!(":memory:") do db
            insert_segment!(db, "segment", "path/to/segment", "fingerprint")
            @test_throws SQLiteException insert_segment!(
                db, "segment", "new/path/to/segment", "new-fingerprint"
            )
        end
    end

    @testset "Path conflict throws SQLiteException" begin
        create_connection!(":memory:") do db
            insert_segment!(db, "segment", "path/to/segment", "fingerprint")
            @test_throws SQLiteException insert_segment!(
                db, "new-segment", "path/to/segment", "new-fingerprint"
            )
        end
    end

    @testset "Fingerprint conflict throws SQLiteException" begin
        create_connection!(":memory:") do db
            insert_segment!(db, "segment", "path/to/segment", "fingerprint")
            @test_throws SQLiteException insert_segment!(
                db, "new-segment", "new-path/to/segment", "fingerprint"
            )
        end
    end

    @testset "Conflicts must not partially update the original row" begin
        create_connection!(":memory:") do db
            insert_segment!(db, "segment", "path/to/segment", "fingerprint")
            @test_throws SQLiteException insert_segment!(
                db, "new-segment", "new-path/to/segment", "fingerprint"
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

@testset "upsert_segment_effort" begin
    @testset "Happy path" begin
        create_connection!(":memory:") do db
            upsert_segment_effort!(db, 1, 10, 123.456, 13, 123456)
            result = DBInterface.execute(
                db,
                "SELECT * FROM segment_efforts WHERE segment_id = ?",
                [10]
            )
            segment_efforts_row = only(NamedTuple(r) for r in result)
            @test segment_efforts_row[:activity_id] == 1
            @test segment_efforts_row[:segment_id] == 10
            @test segment_efforts_row[:elapsed_time_s] == 123.456
            @test segment_efforts_row[:matched_at] == 13
            @test segment_efforts_row[:matcher_version] == 123456
        end
    end

    @testset "Repeating the same match should update the existing row, not add a duplicate" begin
        create_connection!(":memory:") do db
            upsert_segment_effort!(db, 1, 10, 123.456, 13, 123456)
            upsert_segment_effort!(db, 1, 10, 222.0, 14, 654321)
            result = DBInterface.execute(
                db,
                "SELECT * FROM segment_efforts WHERE activity_id = ? AND segment_id = ?",
                [1, 10]
            )
            segment_efforts_row = only(NamedTuple(r) for r in result)
            @test segment_efforts_row[:elapsed_time_s] == 222.0
            @test segment_efforts_row[:matched_at] == 14
            @test segment_efforts_row[:matcher_version] == 654321
        end
    end
end

@testset "select_all" begin
    @testset "No sport returns all rows" begin
        with_activities_db() do db
            @test select_all(db) == [(1, "123"), (2, "456"), (3, "789"), (4, "abc")]
        end
    end

    @testset "Selects only requested sport" begin
        with_activities_db() do db
            @test select_all(db, sport = "cycling") == [(1, "123"), (3, "789"), (4, "abc")]
        end
    end

    @testset "No matches yields empty result" begin
        with_activities_db() do db
            @test select_all(db, sport = "running") == []
        end
    end

    @testset "sport = nothing behaves same as no sport" begin
        with_activities_db() do db
            @test select_all(db, sport = nothing) == [(1, "123"), (2, "456"), (3, "789"), (4, "abc")]
        end
    end
end

@testset "fetch_segment_registration" begin
    @testset "Happy path" begin
        create_connection!(":memory:") do db
            insert_segment!(db, "segment", "path/to/segment", "fingerprint")
            reg = fetch_segment_registration(db, "segment")
            @test reg[:segment_id] == 1
            @test reg[:name] == "segment"
            @test reg[:definition_path] == "path/to/segment"
            @test reg[:definition_fingerprint] == "fingerprint"
        end
    end
end

@testset "fetch_segment_registration all" begin
    @testset "Returns all rows ordered by name" begin
        create_connection!(":memory:") do db
            DBInterface.execute(
                db,
                """
                INSERT INTO segments (name, definition_fingerprint, definition_path)
                VALUES
                    ("c", "fingerprint-c", "path/to/c"),
                    ("b", "fingerprint-b", "path/to/b"),
                    ("a", "fingerprint-a", "path/to/a");
                """
            )
            regs = fetch_segment_registration(db)
            @test regs[1][:name] == "a"
            @test regs[2][:name] == "b"
            @test regs[3][:name] == "c"
            @test regs[1][:definition_path] == "path/to/a"
            @test regs[2][:definition_path] == "path/to/b"
            @test regs[3][:definition_path] == "path/to/c"
            @test regs[1][:definition_fingerprint] == "fingerprint-a"
            @test regs[2][:definition_fingerprint] == "fingerprint-b"
            @test regs[3][:definition_fingerprint] == "fingerprint-c"
        end
    end
end

@testset "fetch_segment_names" begin
    @testset "Happy path and and results ordered by name" begin
        create_connection!(":memory:") do conn
            seed_segments_table!(conn)
            names = fetch_segment_names(conn)
            @test names == ["a", "b", "c"]
        end
    end
end

@testset "remove_segment" begin
    @testset "Removes the requested segment from segments" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            row = remove_segment!(db, "b")
            @test row[:name] == "b"
            @test fetch_segment_names(db) == ["a", "c"]
        end
    end

    @testset "Unknown segment" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            @test remove_segment!(db, "nonexistent") === nothing
            @test fetch_segment_names(db) == ["a", "b", "c"]
        end
    end
end

@testset "remove_segment_efforts" begin
    @testset "Removes the efforts for the given segment_id" begin
        create_connection!(":memory:") do db
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

    @testset "Does nothing for unknown segment_ids" begin
        create_connection!(":memory:") do db
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

@testset "fetch_segment_registration_by_name" begin
    @testset "Happy path" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            row = Lunk.fetch_segment_registration_by_name(db, "b")
            @test row !== nothing
            @test row[:name] == "b"
            @test row[:definition_fingerprint] == "fingerprint-b"
            @test row[:definition_path] == "path/to/b"
        end
    end

    @testset "Missing segment returns nothing" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            @test Lunk.fetch_segment_registration_by_name(db, "nonexistent") === nothing
        end
    end
end

@testset "fetch_segment_registration_by_fingerprint" begin
    @testset "Happy path" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            row = Lunk.fetch_segment_registration_by_fingerprint(db, "fingerprint-b")
            @test row !== nothing
            @test row[:name] == "b"
            @test row[:definition_fingerprint] == "fingerprint-b"
            @test row[:definition_path] == "path/to/b"
        end
    end

    @testset "Missing fingerprint returns nothing" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            @test Lunk.fetch_segment_registration_by_fingerprint(db, "nonexistent-fp") === nothing
        end
    end
end

@testset "fetch_segment_registration_by_path" begin
    @testset "Happy path" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            row = Lunk.fetch_segment_registration_by_path(db, "path/to/b")
            @test row !== nothing
            @test row[:name] == "b"
            @test row[:definition_fingerprint] == "fingerprint-b"
            @test row[:definition_path] == "path/to/b"
        end
    end

    @testset "Missing path returns nothing" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            @test Lunk.fetch_segment_registration_by_path(db, "nonexistent/path") === nothing
        end
    end
end

@testset "remove_segment by id" begin
    @testset "Happy path" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            @test length(fetch_segment_names(db)) == 3

            row = Lunk.remove_segment!(db, 2)
            @test row[:segment_id] == 2
            @test row[:name] == "b"
            @test fetch_segment_names(db) == ["a", "c"]
        end
    end

    @testset "Silent no-op on missing segment_id" begin
        create_connection!(":memory:") do db
            seed_segments_table!(db)
            @test Lunk.remove_segment!(db, 99999) === nothing
            @test fetch_segment_names(db) == ["a", "b", "c"]
        end
    end
end
