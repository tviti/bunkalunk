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
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_start_date(conn, "2026-02-05")
            @test fingerprints == ["123"]
        finally
            close(conn)
        end
    end
end

@testset "select_by_start_date multiple matches" begin
    # two activities with start_time on the same date
    # expect both fingerprints returned
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_start_date(conn, "2026-02-06")
            @test fingerprints == ["456", "789"]
        finally
            close(conn)
        end
    end
end

@testset "select_by_start_date upper boundary" begin
    # activity whose start_time is exactly midnight opening the next day
    # expect it is excluded from the queried date
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_start_date(conn, "2026-02-07")
            @test fingerprints == []
        finally
            close(conn)
        end
    end
end

@testset "select_by_start_date with sport match" begin
    # sport filter that matches seed data
    # expect only activities with sport=="cycling" returned
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_start_date(
                conn,
                "2026-02-06",
                sport = "cycling",
            )
            @test fingerprints == ["789"]
        finally
            close(conn)
        end
    end
end

@testset "select_by_start_date with sport no match" begin
    # sport filter that matches no activities
    # expect empty result
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_start_date(
                conn,
                "2026-02-06",
                sport = "running",
            )
            @test fingerprints == []
        finally
            close(conn)
        end
    end
end

@testset "select_by_start_date with sport nothing" begin
    # sport=nothing should behave identically to the no-sport overload
    # expect all activities in range returned
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_start_date(
                conn,
                "2026-02-06",
                sport = nothing,
            )
            @test fingerprints == ["456", "789"]
        finally
            close(conn)
        end
    end
end

@testset "select_by_time_range" begin
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 5, 30)
            )
            @test fingerprints == ["456"]
        finally
            close(conn)
        end
    end
end

@testset "select_by_time_range multiple matches" begin
    # time range spanning more than one activity
    # expect all matching fingerprints returned
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 15, 30)
            )
            @test fingerprints == ["456", "789"]
        finally
            close(conn)
        end
    end
end

@testset "select_by_time_range upper boundary" begin
    # activity whose start_time equals t1 exactly
    # expect it is excluded (range is half-open: >= t0, < t1)
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_time_range(
                conn,
                DateTime(2026, 2, 5, 5, 00),
                DateTime(2026, 2, 6, 5, 00)
            )
            @test fingerprints == ["123"]
        finally
            close(conn)
        end
    end
end

@testset "select_by_time_range with sport match" begin
    # sport filter that matches seed data
    # expect only activities with sport=="cycling" returned
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 15, 30),
                sport = "cycling",
            )
            @test fingerprints == ["789"]
        finally
            close(conn)
        end
    end
end

@testset "select_by_time_range with sport no match" begin
    # sport filter that matches no activities in range
    # expect empty result
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 15, 30),
                sport = "running",
            )
            @test fingerprints == []
        finally
            close(conn)
        end
    end
end

@testset "select_by_time_range with sport nothing" begin
    # sport=nothing should behave identically to the no-sport overload
    # expect all activities in range returned
    let conn = SQLite.DB()
        try
            create_bunk_tables!(conn)
            seed_activities_table!(conn)
            fingerprints = select_by_time_range(
                conn,
                DateTime(2026, 2, 6, 4, 30),
                DateTime(2026, 2, 6, 15, 30),
                sport = nothing,
            )
            @test fingerprints == ["456", "789"]
        finally
            close(conn)
        end
    end
end

@testset "create_connection with function schema" begin
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
end

@testset "create_connection propagates errors from do-block" begin
    @test_throws ErrorException create_connection(":memory:") do db
        error("test error")
    end
end

@testset "create_connection closes connection on do-block error" begin
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
