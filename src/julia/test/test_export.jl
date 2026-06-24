using Lunk
using Dates
using DelimitedFiles
using Test

include("fixtures.jl")

function create_coordinates()
    return (
        [0.0, 0.1, 0.2],
        [1.0, 1.1, 1.2],
        DateTime.(
            [
                "2026-01-01T00:00:00",
                "2026-01-01T00:01:00",
                "2026-01-01T00:02:00",
            ]
        ),
    )
end

function create_fields()::Vector{AbstractVector}
    return [
        Int64[1, 2, 3],
        Float64[100.0, 102.0, 103.0],
        String["foo", "bar", "baz"],
    ]
end

function create_field_names()::Vector{String}
    return ["ID", "HR", "words"]
end

@testset "write_geocsv!" begin
    @testset "roundtrip" begin
        mktempdir() do dir
            x, y, t = create_coordinates()
            fields = create_fields()
            field_names = create_field_names()
            path = joinpath(dir, "output.csv")

            write_geocsv!(
                path,
                x,
                y,
                t;
                fields = fields,
                field_names = field_names,
                write_sidecar = false,
            )

            data, cleaned = load_csv(path)
            expected = ["Longitude", "Latitude", "timestamp", "ID", "HR", "words"]
            @test length(cleaned) == length(expected)
            for (c, e) in zip(cleaned, expected)
                @test c == e
            end

            @test data[:, 1] == [0.0, 0.1, 0.2]
            @test data[:, 2] == [1.0, 1.1, 1.2]
            @test data[:, 3] == [
                "2026-01-01T00:00:00.000Z",
                "2026-01-01T00:01:00.000Z",
                "2026-01-01T00:02:00.000Z",
            ]
            @test data[:, 4] == [1, 2, 3]
            @test data[:, 5] == [100.0, 102.0, 103.0]
            @test data[:, 6] == ["foo", "bar", "baz"]
        end
    end

    @testset "writes sidecar types file" begin
        mktempdir() do dir
            x, y, t = create_coordinates()
            path = joinpath(dir, "output.csv")
            sidecar_path = joinpath(dir, "output.csvt")

            write_geocsv!(path, x, y, t)

            expected = let io = IOBuffer()
                Lunk.write_csvt!(io, [Float64, Float64, Dates.DateTime])
                seekstart(io)
                read(io, String)
            end

            @test isfile(path)
            @test isfile(sidecar_path)
            @test read(sidecar_path, String) == expected
        end
    end

    @testset "doesn't write sidecar types file" begin
        mktempdir() do dir
            x, y, t = create_coordinates()
            path = joinpath(dir, "output.csv")

            write_geocsv!(path, x, y, t; write_sidecar = false)

            @test isfile(path)
            @test !isfile(joinpath(dir, "output.csvt"))
        end
    end

    @testset "raises when fields and field_names aren't same length" begin
        mktempdir() do dir
            x, y, t = create_coordinates()
            fields = create_fields()
            field_names = create_field_names()
            path = joinpath(dir, "output.csv")

            @test_throws ArgumentError begin
                write_geocsv!(
                    path,
                    x,
                    y,
                    t;
                    fields = [fields[1]],
                    field_names = field_names,
                    write_sidecar = false,
                )
            end
        end
    end

    @testset "raises when coordinate vectors aren't same length" begin
        mktempdir() do dir
            x, y, t = create_coordinates()
            path = joinpath(dir, "output.csv")

            @test_throws ArgumentError begin
                write_geocsv!(path, x[1:(end - 1)], [y[1]], t; write_sidecar = false)
            end
        end
    end

    @testset "raises when path extension isn't csv" begin
        mktempdir() do dir
            x, y, t = create_coordinates()
            path = joinpath(dir, "output.txt")

            @test_throws ArgumentError begin
                write_geocsv!(path, x, y, t; write_sidecar = false)
            end
        end
    end

    @testset "raises when fields_names is nothing but fields isn't" begin
        mktempdir() do dir
            x, y, t = create_coordinates()
            fields = create_fields()
            path = joinpath(dir, "output.csv")

            @test_throws ArgumentError begin
                write_geocsv!(
                    path,
                    x,
                    y,
                    t;
                    fields = fields,
                    field_names = nothing,
                    write_sidecar = false,
                )
            end
        end
    end

    @testset "raises when any column name contains a comma" begin
        mktempdir() do dir
            x, y, t = create_coordinates()
            path = joinpath(dir, "output.csv")

            @test_throws ArgumentError begin
                write_geocsv!(
                    path,
                    x,
                    y,
                    t;
                    time_name = "time,stamp",
                    write_sidecar = false,
                )
            end
        end
    end

    @testset "ignores field_names when fields is nothing" begin
        mktempdir() do dir
            x, y, t = create_coordinates()
            path = joinpath(dir, "output.csv")

            write_geocsv!(
                path,
                x,
                y,
                t;
                fields = nothing,
                field_names = create_field_names(),
                write_sidecar = false,
            )

            data, cleaned = load_csv(path)
            expected = ["Longitude", "Latitude", "timestamp"]
            for (c, e) in zip(cleaned, expected)
                @test c == e
            end

            @test data[:, 1] == [0.0, 0.1, 0.2]
            @test data[:, 2] == [1.0, 1.1, 1.2]
            @test data[:, 3] == [
                "2026-01-01T00:00:00.000Z",
                "2026-01-01T00:01:00.000Z",
                "2026-01-01T00:02:00.000Z",
            ]
        end
    end
end

@testset "write_csvt!" begin
    @testset "roundtrip" begin
        io = IOBuffer()
        Lunk.write_csvt!(io, [Float64, Float64, Dates.DateTime, Int64, Float64, String])
        seekstart(io)
        csvt = read(io, String)
        @test csvt == """"Real","Real","DateTime","Integer64","Real","String"
            """
    end
end
