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
        expected_header = ["Longitude", "Latitude", "timestamp", "activity_id"]
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

        expected_sidecar = let io = IOBuffer()
            Lunk.write_csvt!(io, [Float64, Float64, Dates.DateTime, Int64])
            seekstart(io)
            read(io, String)
        end
        sidecar_path = output_path * "t"
        @test read(sidecar_path, String) == expected_sidecar
        return
    end

    @testset "Roundtrip, creates csv and csvt files" begin
        with_tempdir_context() do ctx, dir
            create_connection!(ctx.db_path) do conn
                create_activities_table!(conn)
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
            create_connection!(ctx.db_path) do conn
                create_activities_table!(conn)
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
            create_connection!(ctx.db_path) do conn
                create_activities_table!(conn)
            end
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
            create_connection!(ctx.db_path) do conn
                create_activities_table!(conn)
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
            create_connection!(ctx.db_path) do conn
                create_activities_table!(conn)
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

            create_connection!(ctx.db_path) do conn
                create_activities_table!(conn)
            end

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
