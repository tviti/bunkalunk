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
            :start_time => 1770267600.0,
            :source_fingerprint => "123",
            :ride_tag => nothing,
            :sport => "basket-weaving",
            :cache_version => 20260101
        )
    )
    insert_activity(
        conn, Dict(
            :start_time => 1770354000.0,
            :source_fingerprint => "456",
            :ride_tag => nothing,
            :sport => "basket-weaving",
            :cache_version => 20260101
        )
    )
    insert_activity(
        conn, Dict(
            :start_time => 1770462000.0,
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

# @testset "select_by_start_date" begin
#     let conn = SQLite.DB()
#         try
#             create_bunk_tables!(conn)
#             seed_activities_table!(conn)
#             fingerprints = select_by_start_date(conn, "2026-02-05")
#             @test length(fingerprints) == 1
#             @test fingerprints[1] == "123"
#         finally
#             close(conn)
#         end
#     end
# end


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
            @test length(fingerprints) == 1
            @test fingerprints[1] == "456"
        finally
            close(conn)
        end
    end
end

@testset "select_by_start_date multiple matches" begin
    # two activities with start_time on the same date
    # expect both fingerprints returned
    @test_skip "not implemented"
end

@testset "select_by_start_date upper boundary" begin
    # activity whose start_time is exactly midnight opening the next day
    # expect it is excluded from the queried date
    @test_skip "not implemented"
end

@testset "select_by_time_range multiple matches" begin
    # time range spanning more than one activity
    # expect all matching fingerprints returned
    @test_skip "not implemented"
end

@testset "select_by_time_range upper boundary" begin
    # activity whose start_time equals t1 exactly
    # expect it is excluded (range is half-open: >= t0, < t1)
    @test_skip "not implemented"
end
