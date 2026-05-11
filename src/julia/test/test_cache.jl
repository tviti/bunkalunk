using Test
using HDF5
using Lunk

function make_cache_file_no_sport(dir)
    path = joinpath(dir, "cache_no_sport.h5")
    h5open(path, "w") do file
        file["time"] = [0.0, 0.1, 0.2]
        file["latitude"] = [1.0, 1.1, 1.2]
        file["longitude"] = [2.0, 2.1, 2.2]
        file["heart_rate"] = [99.0, 99.0, 99.0]
        attributes(file)["start_time"] = 946598400.0
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
    end
    return path
end


function make_cache_file(dir)
    start_time = 946598400.0
    time = [0.0, 0.1, 0.2]
    latitude = [1.0, 1.1, 1.2]
    longitude = [2.0, 2.1, 2.2]
    sport = "basket-weaving"
    heart_rate = [99.0, 99.0, 99.0]

    path = joinpath(dir, "cache.h5")
    h5open(path, "w") do file
        file["time"] = time
        file["latitude"] = latitude
        file["longitude"] = longitude
        file["heart_rate"] = heart_rate
        attributes(file)["start_time"] = start_time
        attributes(file)["sport"] = sport
    end
    return path
end

@testset "read_cache" begin
    mktempdir() do dir
        cache_path = make_cache_file(dir)
        cache_data = read_cache(cache_path)
        @test cache_data.start_time == 946598400.0
        @test cache_data.sport == "basket-weaving"
        @test cache_data.time == [0.0, 0.1, 0.2]
        @test cache_data.latitude == [1.0, 1.1, 1.2]
        @test cache_data.longitude == [2.0, 2.1, 2.2]
        @test cache_data.heart_rate == [99.0, 99.0, 99.0]
    end
end

@testset "read_cache sport absent" begin
    mktempdir() do dir
        cache_path = make_cache_file_no_sport(dir)
        cache_data = read_cache(cache_path)
        @test cache_data.sport === nothing
    end
end

@testset "read_cache heart_rate absent" begin
    mktempdir() do dir
        cache_path = make_cache_file_no_heart_rate(dir)
        cache_data = read_cache(cache_path)
        @test cache_data.heart_rate === nothing
    end
end
