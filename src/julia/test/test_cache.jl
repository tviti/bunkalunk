using Test
using HDF5
using Lunk

include("fixtures.jl")

function make_cache_file_no_sport(dir)
    path = joinpath(dir, "cache_no_sport.h5")
    h5open(path, "w") do file
        file["time"] = [0.0, 0.1, 0.2]
        file["latitude"] = [1.0, 1.1, 1.2]
        file["longitude"] = [2.0, 2.1, 2.2]
        file["heart_rate"] = [99.0, 99.0, 99.0]
        attributes(file)["start_time"] = 946598400.0
        attributes(file)["cache_version"] = Lunk.CACHE_VERSION
    end
    return path
end

function make_cache_file_no_heart_rate(dir)
    path = joinpath(dir, "cache_no_heart_rate.h5")
    h5open(path, "w") do file
        file["time"] = [0.0, 0.1, 0.2]
        file["latitude"] = [1.0, 1.1, 1.2]
        file["longitude"] = [2.0, 2.1, 2.2]
        attributes(file)["start_time"] = 946598400.0
        attributes(file)["sport"] = "basket-weaving"
        attributes(file)["cache_version"] = Lunk.CACHE_VERSION
    end
    return path
end

@testset "read_cache" begin
    @testset "all fields" begin
        mktempdir() do dir
            cache_path = make_cache_file(dir)
            cache_data = read_cache(cache_path)
            @test cache_data.start_time == 946598400.0
            @test cache_data.sport == "basket-weaving"
            @test cache_data.time == [0.0, 0.1, 0.2]
            @test cache_data.latitude == [1.0, 1.1, 1.2]
            @test cache_data.longitude == [2.0, 2.1, 2.2]
            @test cache_data.heart_rate == [99.0, 99.0, 99.0]
            @test cache_data.elevation == [10.0, 11.0, 12.0]
            @test cache_data.distance == [0.0, 1.0, 2.0]
            @test cache_data.speed == [3.0, 3.1, 3.2]
        end
    end

    @testset "throws CacheVersionMismatch error on version mismatch" begin
        mktempdir() do dir
            cache_path = make_cache_file(dir; cache_version = Lunk.CACHE_VERSION - 1)
            @test_throws Lunk.CacheVersionMismatch read_cache(cache_path)
        end
    end

    @testset "sets sport to nothing when absent" begin
        mktempdir() do dir
            cache_path = make_cache_file_no_sport(dir)
            cache_data = read_cache(cache_path)
            @test cache_data.sport === nothing
        end
    end

    @testset "sets heart rate to nothing when absent" begin
        mktempdir() do dir
            cache_path = make_cache_file_no_heart_rate(dir)
            cache_data = read_cache(cache_path)
            @test cache_data.heart_rate === nothing
        end
    end
end

cache_fields(c::CacheData) =
    (c.start_time, c.time, c.latitude, c.longitude, c.sport, c.heart_rate)

@testset "drop_cache_points" begin
    @testset "No NaNs round trip w/ heart_rate" begin
        let cache = CacheData(
                1.0,
                [0.0, 0.1, 0.2],
                [1.0, 1.1, 1.2],
                [2.0, 2.1, 2.2]
                ;
                sport = "cycling",
                heart_rate = [3.0, 3.1, 3.2]
            ),
                expected = CacheData(
                1.0,
                [0.0, 0.1, 0.2],
                [1.0, 1.1, 1.2],
                [2.0, 2.1, 2.2]
                ;
                sport = "cycling",
                heart_rate = [3.0, 3.1, 3.2]
            )
            valid = find_valid_points(cache)
            @test valid == [true, true, true]
            @test cache_fields(drop_cache_points(cache, valid)) == cache_fields(expected)
        end
    end

    @testset "No NaNs round trip no heart_rate" begin
        let cache = CacheData(
                1.0,
                [0.0, 0.1, 0.2],
                [1.0, 1.1, 1.2],
                [2.0, 2.1, 2.2]
                ;
                sport = "cycling",
                heart_rate = nothing
            ),
                expected = CacheData(
                1.0,
                [0.0, 0.1, 0.2],
                [1.0, 1.1, 1.2],
                [2.0, 2.1, 2.2]
                ;
                sport = "cycling",
                heart_rate = nothing
            )
            valid = find_valid_points(cache)
            @test valid == [true, true, true]
            @test cache_fields(drop_cache_points(cache, valid)) == cache_fields(expected)
        end
    end

    @testset "Indexing is maintained after NaN removal" begin
        let cache = CacheData(
                1.0,
                [0.0, 0.1, 0.2, 0.3, 0.4],
                [1.0, NaN, 1.2, 1.3, NaN],
                [2.0, 2.1, NaN, 2.3, 2.4],
                ;
                sport = "cycling",
                heart_rate = [3.0, 3.1, 3.2, 3.3, 3.4]
            ),
                expected = CacheData(
                1.0,
                [0.0, 0.3],
                [1.0, 1.3],
                [2.0, 2.3]
                ;
                sport = "cycling",
                heart_rate = [3.0, 3.3]
            )
            valid = find_valid_points(cache)
            @test valid == [true, false, false, true, false]
            @test cache_fields(drop_cache_points(cache, valid)) == cache_fields(expected)
        end
    end
end
