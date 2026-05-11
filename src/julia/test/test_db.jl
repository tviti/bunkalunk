using Test
using Lunk
using SQLite


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
            start_time TEXT,
            cache_version INT,
            ride_tag TEXT,
            sport TEXT
        )
        """
    )
    return
end


function seed_source_files_table!(conn::SQLite.DB)::Nothing
    DBInterface.execute(
        conn, """
        INSERT INTO source_files (
                source_path,
                content_fingerprint,
                decode_state,
                decode_error
            ) VALUES (
                "a/fake/path.fit",
                "123",
                "pending",
                NULL
            ) 
                """
    )
    DBInterface.execute(
        conn, """
        INSERT INTO source_files (
                source_path,
                content_fingerprint,
                decode_state,
                decode_error
            ) VALUES (
                "a/nother/fake/path.fit",
                "456",
                "success",
                NULL
            ) 
                """
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
            :start_time => "2026-02-05T05:00:00+00:00",
            :source_fingerprint => "123",
            :ride_tag => nothing,
            :sport => "basket-weaving",
            :cache_version => 20260101
        )
    )
    insert_activity(
        conn, Dict(
            :start_time => "2026-02-06T05:00:00+00:00",
            :source_fingerprint => "456",
            :ride_tag => nothing,
            :sport => "basket-weaving",
            :cache_version => 20260101
        )
    )
    insert_activity(
        conn, Dict(
            :start_time => "2026-02-07T11:00:00+00:00",
            :source_fingerprint => "789",
            :ride_tag => nothing,
            :sport => "basket-weaving",
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
            @test length(fingerprints) == 1
            @test fingerprints[1] == "123"
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
                "2026-02-06T04:00:00Z",
                "2026-02-06T05:00:00Z"
            )
            @test length(fingerprints) == 1
            @test fingerprints[1] == "456"
        finally
            close(conn)
        end
    end
end
