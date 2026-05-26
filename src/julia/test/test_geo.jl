using Test
using Lunk

@testset "compute_ecef_r" begin
    a = 6_378_137.0        # WGS-84 semi-major
    b = 6_356_752.314245   # WGS-84 semi-minor

    @testset "known exact points" begin
        let (x, y, z) = compute_ecef_r(0.0, 0.0, 0.0)
            @test x ≈ a atol = 1.0e-3
            @test y ≈ 0.0 atol = 1.0e-3
            @test z ≈ 0.0 atol = 1.0e-3
        end
        let (x, y, z) = compute_ecef_r(90.0, 0.0, 0.0)
            @test x ≈ 0.0 atol = 1.0e-3
            @test y ≈ 0.0 atol = 1.0e-3
            @test z ≈ b atol = 1.0e-3
        end
        let (x, y, z) = compute_ecef_r(-90.0, 0.0, 0.0)
            @test x ≈ 0.0 atol = 1.0e-3
            @test y ≈ 0.0 atol = 1.0e-3
            @test z ≈ -b atol = 1.0e-3
        end
    end

    @testset "latitude reflection symmetry" begin
        for (lat, lon, h) in [(45.0, 30.0, 100.0), (10.0, 120.0, 0.0)]
            x1, y1, z1 = compute_ecef_r(lat, lon, h)
            x2, y2, z2 = compute_ecef_r(-lat, lon, h)
            @test x1 ≈ x2  atol = 1.0e-3
            @test y1 ≈ y2  atol = 1.0e-3
            @test z1 ≈ -z2 atol = 1.0e-3
        end
    end

    @testset "longitude periodicity" begin
        x1, y1, z1 = compute_ecef_r(45.0, 30.0, 0.0)
        x2, y2, z2 = compute_ecef_r(45.0, 30.0 + 360.0, 0.0)
        @test x1 ≈ x2 atol = 1.0e-3
        @test y1 ≈ y2 atol = 1.0e-3
        @test z1 ≈ z2 atol = 1.0e-3
    end

    @testset "equatorial Z is zero" begin
        for lon in [0.0, 45.0, 90.0, 180.0, -90.0]
            _, _, z = compute_ecef_r(0.0, lon, 0.0)
            @test abs(z) < 1.0e-6
        end
    end

    @testset "distance at fixed lat/lon equals height" begin
        let lat = 30.0
            lon = 30.0
            h = 12.5
            x1, y1, z1 = compute_ecef_r(lat, lon, 0.0)
            x2, y2, z2 = compute_ecef_r(lat, lon, h)
            @test sqrt((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2) ≈ h atol = 1.0e-6
        end
    end
end

@testset "crosses_gate" begin
    @testset "no crossing gate parallel" begin
        @test crosses_gate(
            [0.0, 0.0, 0.0], [0.0, 1.0, 0.0],
            [0.0, -1.0, 0.0], [1.0, -1.0, 0.0],
            100
        ) === nothing
    end

    @testset "crosses off-axis gate" begin
        result = crosses_gate(
            [0.0, 0.0, 0.0], [1.0, 1.0, 0.0],
            [-1.0, 0.0, 0.0], [2.0, 1.0, 0.0],
            1.0
        )

        @test result !== nothing
        @test result.t ≈ 0.25 atol = 1.0e-12
        @test result.p ≈ [-0.25, 0.25, 0.0] atol = 1.0e-12
    end

    @testset "crosses genuine 3d gate" begin
        @test crosses_gate(
            [1.0, 2.0, 3.0], [1.0, 1.0, 1.0],
            [0.0, 1.0, 4.0], [3.0, 3.0, 2.0],
            1.0
        ) == (t = 1 / 3, p = [1.0, 5 / 3, 10 / 3])
    end

    @testset "genuine 3d gate outside radius is rejected" begin
        @test crosses_gate(
            [1.0, 2.0, 3.0], [1.0, 1.0, 1.0],
            [0.0, 1.0, 4.0], [3.0, 3.0, 2.0],
            0.4
        ) === nothing
    end

    @testset "crosses right direction" begin
        @test crosses_gate(
            [0.0, 0.0, 0.0], [0.0, 1.0, 0.0],
            [0.0, -1.0, 0.0], [0.0, 1.0, 0.0],
            100
        ) == (t = 0.5, p = [0.0, 0.0, 0.0])
    end

    @testset "crossing outside radius is rejected" begin
        @test crosses_gate(
            [0.0, 0.0, 0.0], [0.0, 1.0, 0.0],
            [0.0, -1.0, 0.0], [1.0, 1.0, 0.0],
            0.49
        ) === nothing
    end

    @testset "crossing at exact radius boundary is rejected" begin
        @test crosses_gate(
            [0.0, 0.0, 0.0], [0.0, 1.0, 0.0],
            [0.0, -1.0, 0.0], [1.0, 1.0, 0.0],
            0.5
        ) === nothing
    end

    @testset "endpoint on gate line is rejected" begin
        @test crosses_gate(
            [0.0, 0.0, 0.0], [0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0], [0.0, 1.0, 0.0],
            100
        ) === nothing
    end

    @testset "crosses wrong direction" begin
        @test crosses_gate(
            [0.0, 0.0, 0.0], [0.0, 1.0, 0.0],
            [0.0, 1.0, 0.0], [0.0, -1.0, 0.0],
            100
        ) === nothing
    end
end

@testset "on_polyline" begin
    @testset "on start vertex" begin
        polyline = [0.0 1.0 2.0; 0.0 0.0 0.0; 0.0 0.0 0.0]

        @test on_polyline([0.0, 0.0, 0.0], polyline, 0.1)
    end

    @testset "on a vertex" begin
        polyline = [0.0 1.0 2.0; 0.0 0.0 0.0; 0.0 0.0 0.0]

        @test on_polyline([1.0, 0.0, 0.0], polyline, 0.1)
        @test on_polyline([0.5, 0.05, 0.0], polyline, 0.1)
    end

    @testset "on end vertex" begin
        polyline = [0.0 1.0 2.0; 0.0 0.0 0.0; 0.0 0.0 0.0]

        @test on_polyline([2.0, 0.0, 0.0], polyline, 0.1)
        @test !on_polyline([0.5, 0.2, 0.0], polyline, 0.1)
    end
end

@testset "haversine_distance" begin
    @test haversine_distance((0.0, 0.0), (0.0, 0.0)) == 0.0
    @test haversine_distance((0.0, 0.0), (0.0, 360.0)) == 0.0
    @test haversine_distance((0.0, 0.0), (360.0, 0.0)) == 0.0

    @test haversine_distance((0.0, 0.0), (0.0, 180.0)) == π * 6371.2e3
    @test haversine_distance((0.0, 0.0), (0.0, -180.0)) == π * 6371.2e3

    @test haversine_distance((0.0, 0.0), (180.0, 0.0)) == π * 6371.2e3
    @test haversine_distance((0.0, 0.0), (-180.0, 0.0)) == π * 6371.2e3

    @test haversine_distance((45.0, 0.0), (45.0, 90.0)) ≈ 6371.2e3 * π / 3
end
