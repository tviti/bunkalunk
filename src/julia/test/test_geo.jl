using Test
using Lunk

@testset "haversine_distance" begin
    @test haversine_distance((0.0, 0.0), (0.0, 0.0)) == 0.0
    @test haversine_distance((0.0, 0.0), (0.0, 360.0)) == 0.0
    @test haversine_distance((0.0, 0.0), (360.0, 0.0)) == 0.0

    @test haversine_distance((0.0, 0.0), (0.0, 180.0)) == π * 6371.2e3
    @test haversine_distance((0.0, 0.0), (0.0, -180.0)) == π * 6371.2e3

    @test haversine_distance((0.0, 0.0), (180.0, 0.0)) == π * 6371.2e3
    @test haversine_distance((0.0, 0.0), (-180.0, 0.0)) == π * 6371.2e3

    @test haversine_distance((45.0, 0.0), (45.0, 90.0)) ≈ 6371.2 * π / 3
end
