using Test
using SQLite
using Lunk
using Logging
using Dates

include("fixtures.jl")

@testset "run_activity_export" begin

    function output_pair_exists(path)
        return isfile(path) == true && isfile(path * "t") == true
    end

    function assert_output_data(output_path)
        data, header = load_csv(output_path)
        expected_header = [
            "Longitude",
            "Latitude",
            "timestamp",
            "activity_id",
            "heart_rate",
            "elevation",
            "speed",
            "distance",
        ]
        expected_types = [
            Float64,
            Float64,
            Dates.DateTime,
            Int64,
            Float64,
            Float64,
            Float64,
            Float64,
        ]
        @test length(header) == length(expected_header)
        for (h, e) in zip(header, expected_header)
            @test h == e
        end
        @test data[:, 1] == Float64[2.0, 2.1, 2.2]
        @test data[:, 2] == Float64[1.0, 1.1, 1.2]
        @test data[:, 3] == [
            "1970-01-01T00:00:00.000Z"
            "1970-01-01T00:00:00.100Z"
            "1970-01-01T00:00:00.200Z"
        ]
        @test data[:, 4] == Int64[1, 1, 1]
        @test all(isa.(data[:, 4], Int64))
        @test data[:, 5] == Float64[99.0, 99.0, 99.0]
        @test data[:, 6] == Float64[10.0, 11.0, 12.0]
        @test data[:, 7] == Float64[3.0, 3.1, 3.2]
        @test data[:, 8] == Float64[0.0, 1.0, 2.0]

        expected_sidecar = let io = IOBuffer()
            Lunk.write_csvt!(io, expected_types)
            seekstart(io)
            read(io, String)
        end
        sidecar_path = output_path * "t"
        @test read(sidecar_path, String) == expected_sidecar
        return
    end

    @testset "Roundtrip, creates csv and csvt files" begin
        with_tempdir_context() do ctx, dir
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                make_registered_cache_file!(conn, dir)
            end
            output_path = joinpath(dir, "activity.csv")
            args = Dict{String, Any}(
                "activity_ids" => Int64[1],
                "output" => output_path
            )
            @test Lunk.run_activity_export(args, ctx) == 0
            assert_output_data(output_path)
        end
    end

    @testset "Rejects non-csv extension" begin
        with_tempdir_context() do ctx, dir
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                make_registered_cache_file!(conn, dir)
            end
            output_path = joinpath(dir, "activity.notcsv")
            args = Dict{String, Any}(
                "activity_ids" => Int64[1],
                "output" => output_path
            )
            result = @test_logs (:error,) Lunk.run_activity_export(args, ctx)
            @test result == 1
            @test !output_pair_exists(output_path)
        end
    end

    @testset "Returns non-zero for nonexistent activity_id" begin
        with_tempdir_context() do ctx, dir
            create_bunk_tables!(ctx.db_path)
            output_path = joinpath(dir, "activity.csv")
            args = Dict{String, Any}(
                "activity_ids" => Int64[1],
                "output" => output_path
            )
            result = @test_logs (:error,) Lunk.run_activity_export(args, ctx)
            @test result == 1
            @test !output_pair_exists(output_path)
        end
    end

    @testset "Returns one if any activity_id is nonexistent" begin
        with_tempdir_context() do ctx, dir
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                make_registered_cache_file!(conn, dir)
                make_registered_cache_file!(conn, dir; fingerprint = "cache-2")
            end
            output_path = joinpath(dir, "activity.csv")
            args = Dict{String, Any}(
                "activity_ids" => Int64[1, 99, 2],
                "output" => output_path
            )

            result = @test_logs (:error,) Lunk.run_activity_export(args, ctx)
            @test result == 1
            @test !output_pair_exists(output_path)
        end
    end

    @testset "Overwrites existing CSV+CSVT on success" begin
        with_tempdir_context() do ctx, dir
            output_path = joinpath(dir, "activity.csv")
            open(output_path, "w") do f
                println(f, "test-csv")
            end
            open(output_path * "t", "w") do f
                println(f, "test-csvt")
            end
            create_bunk_tables!(ctx.db_path)
            create_connection!(ctx.db_path) do conn
                make_registered_cache_file!(conn, dir)
            end
            args = Dict{String, Any}(
                "activity_ids" => Int64[1],
                "output" => output_path
            )
            @test Lunk.run_activity_export(args, ctx) == 0
            assert_output_data(output_path)
        end
    end

    @testset "Invalid activity failure leaves existing CSV+CSVT intact" begin
        with_tempdir_context() do ctx, dir
            output_path = joinpath(dir, "activity.csv")
            open(output_path, "w") do f
                println(f, "test-csv")
            end
            open(output_path * "t", "w") do f
                println(f, "test-csvt")
            end

            create_bunk_tables!(ctx.db_path)

            args = Dict{String, Any}(
                "activity_ids" => Int64[1],
                "output" => output_path
            )
            result = @test_logs (:error,) Lunk.run_activity_export(args, ctx)
            @test result == 1

            open(output_path, "r") do f
                @test read(f, String) == "test-csv\n"
            end
            open(output_path * "t", "r") do f
                @test read(f, String) == "test-csvt\n"
            end

        end
    end
end

@testset "activity summary" begin
    activity = CacheData(
        946598400.0,
        [0.0, 10.0, 20.0],
        [1.0, 1.1, 1.2],
        [2.0, 2.1, 2.2],
        sport = "cycling",
        heart_rate = [90.0, NaN, 120.0],
        elevation = [10.0, 11.0, 12.0],
        distance = [0.0, 1.0, 2.0],
        speed = [3.0, 3.1, 3.2],
    )

    summary = Lunk.activity_summary(1, activity)
    @test summary.distance.total_km == 2.0
    @test summary.distance.total_mi ≈ 1.242742384474668
    @test summary.speed.median_kmh == 3.1
    @test summary.speed.median_mph ≈ 1.926250695197955
    @test summary.elevation.min_m == 10.0
    @test summary.elevation.min_ft ≈ 32.8084
    @test summary.heart_rate.median_bpm == 105.0
    @test summary.heart_rate.min_bpm == 90.0
    @test summary.heart_rate.max_bpm == 120.0
end

function register_matchable_segment!(conn, dir; name = "segment")
    segment_path = joinpath(dir, name * ".osm")
    write_minimal_osm(segment_path; name = name)
    fingerprint = open(segment_path, "r") do f
        compute_fingerprint(f)
    end
    insert_segment!(
        conn,
        name,
        abspath(segment_path),
        fingerprint,
        make_synthetic_segment()
    )
    return fetch_segment_registration_by_name(conn, name)
end

@testset "activity_match" begin
    @testset "Happy path" begin
        with_tempdir_context() do ctx, dir
            create_connection!(ctx.db_path) do conn
                cache = make_cache_affirmative_match()
                register_matchable_segment!(conn, dir)
                make_registered_cache_file!(
                    conn,
                    dir;
                    fingerprint = "cache",
                    time = cache.time,
                    latitude = cache.latitude,
                    longitude = cache.longitude,
                    heart_rate = cache.heart_rate,
                    elevation = nothing,
                    distance = nothing,
                    speed = nothing,
                    x_min = 0.0,
                    x_max = 0.0,
                    y_min = -0.00005,
                    y_max = 0.00025,
                )
            end

            @test Lunk.activity_match(1; ctx = ctx) == 0

            create_connection!(ctx.db_path) do conn
                registration = fetch_segment_registration_by_name(conn, "segment")
                efforts = fetch_segment_efforts_by_pairing(
                    conn, registration.segment_id, 1
                )

                @test length(efforts) == 1
                if length(efforts) == 1
                    effort = only(efforts)
                    @test isapprox(effort.elapsed_time_s, 20.0; atol = 1.0e-9)
                    @test effort.matcher_version == Lunk.MATCHER_VERSION
                    @test effort.idx_start == 1
                    @test effort.idx_end == 4
                end
            end
        end
    end

    @testset "rematch removes stale efforts" begin
        with_tempdir_context() do ctx, dir
            create_connection!(ctx.db_path) do conn
                cache = make_cache_affirmative_match()
                registration = register_matchable_segment!(conn, dir)
                make_registered_cache_file!(
                    conn,
                    dir;
                    fingerprint = "cache",
                    time = cache.time,
                    latitude = cache.latitude,
                    longitude = cache.longitude,
                    heart_rate = cache.heart_rate,
                    elevation = nothing,
                    distance = nothing,
                    speed = nothing,
                    x_min = 0.0,
                    x_max = 0.0,
                    y_min = -0.00005,
                    y_max = 0.00025,
                )
                insert_segment_effort!(
                    conn,
                    1,
                    registration.segment_id,
                    999.0,
                    1234,
                    Lunk.MATCHER_VERSION - 1,
                    9,
                    10,
                )
            end

            @test Lunk.activity_match(1; ctx = ctx) == 0

            create_connection!(ctx.db_path) do conn
                registration = fetch_segment_registration_by_name(conn, "segment")
                efforts = fetch_segment_efforts_by_pairing(
                    conn, registration.segment_id, 1
                )

                @test length(efforts) == 1
                if length(efforts) == 1
                    effort = only(efforts)
                    @test effort.matcher_version == Lunk.MATCHER_VERSION
                    @test isapprox(effort.elapsed_time_s, 20.0; atol = 1.0e-9)
                    @test effort.idx_start == 1
                    @test effort.idx_end == 4
                end
            end
        end
    end

    @testset "Omitting activity_id matches most recent activity" begin
        with_tempdir_context() do ctx, dir
            create_connection!(ctx.db_path) do conn
                cache = make_cache_affirmative_match()
                register_matchable_segment!(conn, dir)
                make_registered_cache_file!(
                    conn,
                    dir;
                    fingerprint = "cache-old",
                    start_time = 946598400.0,
                    time = cache.time,
                    latitude = cache.latitude,
                    longitude = cache.longitude,
                    heart_rate = cache.heart_rate,
                    elevation = nothing,
                    distance = nothing,
                    speed = nothing,
                    x_min = 0.0,
                    x_max = 0.0,
                    y_min = -0.00005,
                    y_max = 0.00025,
                )
                make_registered_cache_file!(
                    conn,
                    dir;
                    fingerprint = "cache-new",
                    start_time = 946598500.0,
                    time = cache.time,
                    latitude = cache.latitude,
                    longitude = cache.longitude,
                    heart_rate = cache.heart_rate,
                    elevation = nothing,
                    distance = nothing,
                    speed = nothing,
                    x_min = 0.0,
                    x_max = 0.0,
                    y_min = -0.00005,
                    y_max = 0.00025,
                )
            end

            @test Lunk.activity_match(; ctx = ctx) == 0

            create_connection!(ctx.db_path) do conn
                registration = fetch_segment_registration_by_name(conn, "segment")
                @test isempty(fetch_segment_efforts_by_pairing(conn, registration.segment_id, 1))
                @test length(fetch_segment_efforts_by_pairing(conn, registration.segment_id, 2)) == 1
            end
        end
    end

    @testset "Returns error for nonexistent activity" begin
        with_tempdir_context() do ctx, dir
            result = @test_logs (:error,) Lunk.activity_match(1; ctx = ctx)
            @test result == 1
        end
    end

    @testset "Returns error for activity read failure" begin
        with_tempdir_context() do ctx, dir
            create_connection!(ctx.db_path) do conn
                insert_activity!(
                    conn,
                    Dict(
                        :start_time => 946598400.0,
                        :source_fingerprint => "cache",
                        :ride_tag => nothing,
                        :sport => "cycling",
                        :cache_version => 20260624,
                        :x_min => 0.0,
                        :x_max => 0.0,
                        :y_min => -0.00005,
                        :y_max => 0.00025,
                    )
                )
            end

            result = @test_logs (:error,) Lunk.activity_match(1; ctx = ctx)
            @test result == 1
        end
    end
end

@testset "activity_match_update!" begin
    @testset "Returns affirmative matches for overlapping segments" begin
        with_tempdir_context() do ctx, dir
            create_connection!(ctx.db_path) do conn
                cache = make_cache_affirmative_match()
                segment = make_synthetic_segment()
                insert_segment!(
                    conn,
                    "segment",
                    "path/to/segment",
                    "fingerprint",
                    segment
                )
                make_registered_cache_file!(
                    conn,
                    dir;
                    fingerprint = "cache",
                    time = cache.time,
                    latitude = cache.latitude,
                    longitude = cache.longitude,
                    heart_rate = cache.heart_rate,
                    elevation = nothing,
                    distance = nothing,
                    speed = nothing,
                    x_min = 0.0,
                    x_max = 0.0,
                    y_min = -0.00005,
                    y_max = 0.00025,
                )
                registration = fetch_segment_registration_by_name(conn, "segment")
                segment_ecef = compute_ecef_r(
                    segment.latitude,
                    segment.longitude,
                    Lunk.FIXED_HEIGHT
                )
                payload_cache = Lunk.ActivitiesPayload()

                results = Lunk.activity_match_update!(
                    conn,
                    registration,
                    segment_ecef,
                    payload_cache,
                    ctx.activity_store
                )

                @test length(results) == 1
                if length(results) == 1
                    result = only(results)
                    @test result.activity_id == 1
                    @test isapprox(result.segment_time, 20.0; atol = 1.0e-9)
                    @test result.idx_start == 1
                    @test result.idx_end == 4
                end
                @test issetequal(keys(payload_cache), [1])
            end
        end
    end

    @testset "Returns empty array for overlapping non-affirmative segment" begin
        with_tempdir_context() do ctx, dir
            create_connection!(ctx.db_path) do conn
                cache = make_cache_partial_overlap()
                segment = make_synthetic_segment()
                insert_segment!(
                    conn,
                    "segment",
                    "path/to/segment",
                    "fingerprint",
                    segment
                )
                make_registered_cache_file!(
                    conn,
                    dir;
                    fingerprint = "cache",
                    time = cache.time,
                    latitude = cache.latitude,
                    longitude = cache.longitude,
                    heart_rate = cache.heart_rate,
                    elevation = nothing,
                    distance = nothing,
                    speed = nothing,
                    x_min = 0.0,
                    x_max = 0.001,
                    y_min = -0.00005,
                    y_max = 0.00018,
                )
                registration = fetch_segment_registration_by_name(conn, "segment")
                segment_ecef = compute_ecef_r(
                    segment.latitude,
                    segment.longitude,
                    Lunk.FIXED_HEIGHT
                )
                payload_cache = Lunk.ActivitiesPayload()

                results = Lunk.activity_match_update!(
                    conn,
                    registration,
                    segment_ecef,
                    payload_cache,
                    ctx.activity_store
                )

                @test isempty(results)
                @test issetequal(keys(payload_cache), [1])
            end
        end
    end

    @testset "Raises on activity load error" begin
        with_tempdir_context() do ctx, dir
            create_connection!(ctx.db_path) do conn
                segment = make_synthetic_segment()
                insert_segment!(
                    conn,
                    "segment",
                    "path/to/segment",
                    "fingerprint",
                    segment
                )
                insert_activity!(
                    conn,
                    Dict(
                        :start_time => 946598400.0,
                        :source_fingerprint => "cache",
                        :ride_tag => nothing,
                        :sport => "cycling",
                        :cache_version => 20260624,
                        :x_min => 0.0,
                        :x_max => 0.0,
                        :y_min => -0.00005,
                        :y_max => 0.00025,
                    )
                )
                registration = fetch_segment_registration_by_name(conn, "segment")
                segment_ecef = compute_ecef_r(
                    segment.latitude,
                    segment.longitude,
                    Lunk.FIXED_HEIGHT
                )

                @test_throws Exception Lunk.activity_match_update!(
                    conn,
                    registration,
                    segment_ecef,
                    Lunk.ActivitiesPayload(),
                    ctx.activity_store
                )
            end
        end
    end
end

@testset "activity_match_transaction!" begin
    @testset "Raises on activity_payload with more than one key" begin
        with_tmp_bunk_db!() do dir, db_path
            create_connection!(db_path) do conn
                seed_segments_table!(conn)
                activity_context = ActivityContext(make_cache_lap_then_abort())
                activity_payload = Lunk.ActivitiesPayload(
                    1 => activity_context,
                    2 => activity_context,
                )
                registration = fetch_segment_registration_by_name(conn, "c")

                @test_throws ArgumentError Lunk.activity_match_transaction!(
                    conn,
                    registration,
                    zeros(Float64, 3, 2),
                    activity_payload,
                    Lunk.ActivitiesPayload(),
                    false,
                    IOBuffer(),
                )
            end
        end
    end
end
