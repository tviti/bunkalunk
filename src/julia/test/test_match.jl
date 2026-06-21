using Test
using Dates
using Lunk

function make_synthetic_segment()::Segment
    return Segment(
        "synthetic segment",
        [0.0, 0.0001, 0.0002],
        [0.0, 0.0, 0.0]
    )
end

function make_cache_affirmative_match()::CacheData
    return CacheData(
        946598400.0,
        [0.0, 10.0, 20.0, 30.0],
        [-0.00005, 0.00005, 0.00015, 0.00025],
        [0.0, 0.0, 0.0, 0.0],
        sport = "cycling",
        heart_rate = nothing
    )
end

function make_cache_partial_overlap()::CacheData
    return CacheData(
        946598400.0,
        [0.0, 10.0, 20.0, 30.0, 40.0],
        [-0.00005, 0.00005, 0.00015, 0.00018, 0.00018],
        [0.0, 0.0, 0.0, 0.001, 0.001],
        sport = "cycling",
        heart_rate = nothing
    )
end

function make_cache_no_overlap()::CacheData
    return CacheData(
        946598400.0,
        [0.0, 10.0, 20.0, 30.0],
        [-0.00005, -0.00003, -0.00002, -0.00001],
        [0.001, 0.001, 0.001, 0.001],
        sport = "cycling",
        heart_rate = nothing
    )
end

@testset "match_to_activities" begin
    @testset "affirmative match" begin
        segment = make_synthetic_segment()
        cache = make_cache_affirmative_match()
        activities = Dict{Int, CacheData}(7 => cache)

        lower = floor(Int, time())
        results = match_to_activities(segment, activities)
        upper = ceil(Int, time())

        @test length(results) == 1
        result = results[1]
        @test result.activity_id == 7
        @test result.activity_date == unix2datetime(cache.start_time)
        @test isapprox(result.segment_time, 20.0; atol = 1e-9)
        @test lower <= result.matched_at <= upper
    end

    @testset "partial overlap produces no match" begin
        segment = make_synthetic_segment()
        cache = make_cache_partial_overlap()
        activities = Dict{Int, CacheData}(8 => cache)

        results = match_to_activities(segment, activities)
        @test isempty(results)
    end

    @testset "no overlap produces no match" begin
        segment = make_synthetic_segment()
        cache = make_cache_no_overlap()
        activities = Dict{Int, CacheData}(9 => cache)

        results = match_to_activities(segment, activities)
        @test isempty(results)
    end

    @testset "leading NaN GPS rows do not change valid match" begin
        segment = make_synthetic_segment()
        clean = make_cache_affirmative_match()
        with_nans = CacheData(
            clean.start_time,
            vcat([-20.0, -10.0], clean.time),
            vcat([NaN, NaN], clean.latitude),
            vcat([NaN, NaN], clean.longitude),
            sport = clean.sport,
            heart_rate = nothing,
        )
        activities = Dict{Int, CacheData}(
            13 => clean,
            14 => with_nans,
        )

        results = match_to_activities(segment, activities)

        @test length(results) == 2
        clean_result = only(filter(r -> r.activity_id == 13, results))
        nan_result = only(filter(r -> r.activity_id == 14, results))
        @test nan_result.activity_date == clean_result.activity_date
        @test isapprox(nan_result.segment_time, clean_result.segment_time; atol = 1e-9)
    end

    @testset "mixed activity set returns only affirmative match" begin
        segment = make_synthetic_segment()
        affirmative = make_cache_affirmative_match()
        partial = make_cache_partial_overlap()
        no_overlap = make_cache_no_overlap()
        activities = Dict{Int, CacheData}(
            10 => affirmative,
            11 => partial,
            12 => no_overlap,
        )

        lower = floor(Int, time())
        results = match_to_activities(segment, activities)
        upper = ceil(Int, time())

        @test length(results) == 1
        result = results[1]
        @test result.activity_id == 10
        @test result.activity_date == unix2datetime(affirmative.start_time)
        @test isapprox(result.segment_time, 20.0; atol = 1e-9)
        @test lower <= result.matched_at <= upper
    end
end
