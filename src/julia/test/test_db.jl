using Test
using Lunk
using SQLite
using Dates


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
    DBInterface.execute(
        conn, """
        CREATE TABLE IF NOT EXISTS activities (
            activity_id INTEGER PRIMARY KEY,
            source_fingerprint TEXT UNIQUE NOT NULL,
            start_time REAL,
            cache_version INT,
            ride_tag TEXT,
            sport TEXT
        )
        """
    )
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
    with_activities_db() do conn
        @test select_by_start_date(conn, "2026-02-05") == ["123"]
    end
    with_activities_db() do conn
        # multiple matches: two activities with start_time on the same date
        @test select_by_start_date(conn, "2026-02-06") == ["456", "789"]
    end
    with_activities_db() do conn
        # upper boundary: exactly midnight opening the next day should be excluded
        @test select_by_start_date(conn, "2026-02-07") == []
    end
    with_activities_db() do conn
        # sport filter that matches seed data — only cycling returned
        @test select_by_start_date(conn, "2026-02-06", sport = "cycling") == ["789"]
    end
    with_activities_db() do conn
        # sport filter that matches no activities — empty result
        @test select_by_start_date(conn, "2026-02-06", sport = "running") == []
    end
    with_activities_db() do conn
        # sport=nothing behaves identically to the no-sport overload
        @test select_by_start_date(conn, "2026-02-06", sport = nothing) == ["456", "789"]
    end
end

@testset "select_by_time_range" begin
    with_activities_db() do conn
        @test select_by_time_range(
            conn,
            DateTime(2026, 2, 6, 4, 30),
            DateTime(2026, 2, 6, 5, 30)
        ) == ["456"]
    end

    with_activities_db() do conn
        # multiple matches: time range spanning more than one activity
        @test select_by_time_range(
            conn,
            DateTime(2026, 2, 6, 4, 30),
            DateTime(2026, 2, 6, 15, 30)
        ) == ["456", "789"]
    end

    with_activities_db() do conn
        # upper boundary: start_time exactly equal to t1 is excluded (range is >= t0, < t1)
        @test select_by_time_range(
            conn,
            DateTime(2026, 2, 5, 5, 00),
            DateTime(2026, 2, 6, 5, 00)
        ) == ["123"]
    end

    with_activities_db() do conn
        # sport filter that matches seed data — only cycling returned
        @test select_by_time_range(
            conn,
            DateTime(2026, 2, 6, 4, 30),
            DateTime(2026, 2, 6, 15, 30),
            sport = "cycling"
        ) == ["789"]
    end

    with_activities_db() do conn
        # sport filter that matches no activities in range — empty result
        @test select_by_time_range(
            conn,
            DateTime(2026, 2, 6, 4, 30),
            DateTime(2026, 2, 6, 15, 30),
            sport = "running"
        ) == []
    end

    with_activities_db() do conn
        # sport=nothing behaves identically to the no-sport overload
        @test select_by_time_range(
            conn,
            DateTime(2026, 2, 6, 4, 30),
            DateTime(2026, 2, 6, 15, 30),
            sport = nothing
        ) == ["456", "789"]
    end
end

@testset "create_connection" begin
    # verifies table schemas created by create_connection
    create_connection(":memory:") do db
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

    # errors thrown inside the do-block should propagate out
    @test_throws ErrorException create_connection(":memory:") do db
        error("test error")
    end

    # connection is closed even when the do-block raises an error
    ref = Ref{SQLite.DB}()
    try
        create_connection(":memory:") do db
            ref[] = db
            error("test error")
        end
    catch
    end
    @test !SQLite.isopen(ref[])
end

@testset "upsert_segment" begin
    # Happy path
    create_connection(":memory:") do db
        upsert_segment(db, "segment", "path/to/segment", "fingerprint")
        result = DBInterface.execute(
            db,
            "SELECT * FROM segments WHERE name = ?",
            ["segment"]
        )
        row = only(NamedTuple(row) for row in result)
        @test row[:name] == "segment"
        @test row[:definition_path] == "path/to/segment"
        @test row[:definition_fingerprint] == "fingerprint"

        # Conflict updates row
        upsert_segment(db, "segment", "new/path/to/segment", "new-fingerprint")
        result = DBInterface.execute(
            db,
            "SELECT * FROM segments WHERE name = ?",
            ["segment"]
        )
        segment_row = only(NamedTuple(r) for r in result)
        @test segment_row[:name] == "segment"
        @test segment_row[:definition_path] == "new/path/to/segment"
        @test segment_row[:definition_fingerprint] == "new-fingerprint"
    end
end

@testset "upsert_segment_effort" begin
    create_connection(":memory:") do db
        # Happy path
        upsert_segment_effort(db, 1, 10, 123.456, 13, 123456)
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

        # Repeating the same match should update the existing row, not add a duplicate.
        upsert_segment_effort(db, 1, 10, 222.0, 14, 654321)
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

@testset "fetch_segment_path" begin
    # Happy path
    create_connection(":memory:") do db
        upsert_segment(db, "segment", "path/to/segment", "fingerprint")
        @test fetch_segment_path(db, "segment") == "path/to/segment"
    end
end

@testset "fetch_segment_names" begin
    # Happy path and and results ordered by name
    create_connection(":memory:") do db
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
        names = fetch_segment_names(db)
        @test names == ["a", "b", "c"]
    end
end
