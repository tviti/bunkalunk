using Test
using Lunk

function write_test_segment(dir::String, data::String; extension = ".osm")::String
    path = joinpath(dir, "segment" * extension)
    write(path, data)
    return path
end

@testset "read_segment" begin
    @testset "unsupported extension throws" begin
        mktempdir() do dir
            path = joinpath(dir, "notasegment.bin")
            @test_throws r"ArgumentError: unsupported file extension: \".bin\"" read_segment(path)
        end
    end
end

@testset "read_segment OSM" begin

    @testset "happy path" begin
        # minimal valid file: one way, N nodes, nd refs match, name tag present
        xml = """
            <osm>
                <node id="1" visible="true" lat="1.5" lon="2.25" />
                <way id="1" visible="true">
                     <nd ref="1" />
                     <tag k="name" v="segment" />
                </way>
            </osm> 
        """
        mktempdir() do dir
            path = write_test_segment(dir, xml)
            segment = read_segment(path)
            @test segment.name == "segment"
            @test segment.latitude == [1.5]
            @test segment.longitude == [2.25]
        end
    end

    @testset "no name tag" begin
        # name defaults to ""
        xml = """
            <osm>
                <node id="1" visible="true" lat="1.5" lon="2.25" />
                <way id="1" visible="true">
                     <nd ref="1" />
                </way>
            </osm> 
        """
        mktempdir() do dir
            path = write_test_segment(dir, xml)
            @test_logs (:warn, "Segment file $path has no name") begin
                segment = read_segment(path)
                @test segment.name == ""
                @test segment.latitude == [1.5]
                @test segment.longitude == [2.25]
            end
        end
    end

    @testset "wrong root tag" begin
        # root element is not <osm>, expect ArgumentError
        xml = """
            <notosm>
                <node id="1" visible="true" lat="1.5" lon="2.25" />
                <way id="1" visible="true">
                     <nd ref="1" />
                     <tag k="name" v="segment" />
                </way>
            </notosm> 
        """
        mktempdir() do dir
            path = write_test_segment(dir, xml)
            @test_throws r"ArgumentError:.*tag is not 'osm', got" read_segment(path)
        end
    end

    @testset "no nodes" begin
        # way is present but file contains no node elements, expect ArgumentError
        xml = """
            <osm>
                <way id="1" visible="true">
                     <nd ref="1" />
                     <tag k="name" v="segment" />
                </way>
            </osm> 
        """
        mktempdir() do dir
            path = write_test_segment(dir, xml)
            @test_throws r"ArgumentError:.*no nodes" read_segment(path)
        end
    end

    @testset "no ways" begin
        # file contains nodes but no way element, expect ArgumentError
        xml = """
            <osm>
                <node id="1" visible="true" lat="1.5" lon="2.25" />
                <node id="2" visible="true" lat="1.6" lon="2.35" />
            </osm> 
        """
        mktempdir() do dir
            path = write_test_segment(dir, xml)
            @test_throws r"ArgumentError:.*must contain exactly one way" read_segment(path)
        end
    end

    @testset "multiple ways" begin
        # file contains more than one way element, expect ArgumentError
        xml = """
            <osm>
                <node id="1" visible="true" lat="1.5" lon="2.25" />
                <node id="2" visible="true" lat="1.6" lon="2.35" />
                <way id="1" visible="true">
                     <nd ref="1" />
                     <tag k="name" v="segment one" />
                </way>
                <way id="2" visible="true">
                     <nd ref="2" />
                     <tag k="name" v="segment two" />
                </way>
            </osm> 
        """
        mktempdir() do dir
            path = write_test_segment(dir, xml)
            @test_throws r"ArgumentError:.*must contain exactly one way" read_segment(path)
        end
    end

    @testset "dangling nd ref" begin
        # way references a node id not present in the file, expect ArgumentError
        xml = """
            <osm>
                <node id="1" visible="true" lat="1.5" lon="2.25" />
                <way id="1" visible="true">
                     <nd ref="1" />
                     <nd ref="999" />
                     <tag k="name" v="segment" />
                </way>
            </osm> 
        """
        mktempdir() do dir
            path = write_test_segment(dir, xml)
            @test_throws r"ArgumentError:.*no matching node" read_segment(path)
        end
    end

    @testset "node ordering" begin
        # nodes declared in reverse order relative to nd refs;
        # confirm lat/lon are assembled in way order, not declaration order
        xml = """
            <osm>
                <node id="3" visible="true" lat="1.3" lon="2.3" />
                <node id="2" visible="true" lat="1.2" lon="2.2" />
                <node id="1" visible="true" lat="1.1" lon="2.1" />
                <way id="1" visible="true">
                     <nd ref="1" />
                     <nd ref="2" />
                     <nd ref="3" />
                     <tag k="name" v="segment" />
                </way>
            </osm> 
        """
        mktempdir() do dir
            path = write_test_segment(dir, xml)
            segment = read_segment(path)
            @test segment.name == "segment"
            @test segment.latitude == [1.1, 1.2, 1.3]
            @test segment.longitude == [2.1, 2.2, 2.3]
        end
    end

end

@testset "read_segment geojson" begin
    @testset "Roundtrip" begin
        json = """
        {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [[1.5, 2.25], [2.5, 3.25]]
            },
            "properties": {
                "name": "segment"
            }
        }
        """
        segment = mktempdir() do dir
            path = write_test_segment(dir, json, extension = ".geojson")
            read_segment(path)
        end
        @test segment.name == "segment"
        @test segment.latitude == [2.25, 3.25]
        @test segment.longitude == [1.5, 2.5]
    end

    @testset "rejects non-LineString Feature" begin
        json = """
        {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [1.5, 2.25]
            },
            "properties": {
                "name": "point"
            }
        }
        """
        mktempdir() do dir
            path = write_test_segment(dir, json, extension = ".geojson")
            @test_throws ArgumentError read_segment(path)
        end
    end

    @testset "rejects FeatureCollection" begin
        json = """
        {
            "type": "FeatureCollection",
            "features": []
        }
        """
        mktempdir() do dir
            path = write_test_segment(dir, json, extension = ".geojson")
            @test_throws ArgumentError read_segment(path)
        end
    end

    @testset "rejects Feature-less file" begin
        json = """
        {
          "type": "LineString",
          "coordinates": [
            [0.0, 0.0],
            [1.0, 1.0]
          ]
        }
        """
        mktempdir() do dir
            path = write_test_segment(dir, json, extension = ".geojson")
            @test_throws ArgumentError read_segment(path)
        end
    end

    @testset "no name property" begin
        json = """
        {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [[1.5, 2.25], [2.5, 3.25]]
            },
            "properties": {}
        }
        """
        mktempdir() do dir
            path = write_test_segment(dir, json, extension = ".geojson")
            segment = @test_logs (:warn,) read_segment(path)
            @test segment.name == ""
            @test segment.latitude == [2.25, 3.25]
            @test segment.longitude == [1.5, 2.5]
        end
    end

    @testset "missing properties attr" begin
        json = """
        {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [[1.5, 2.25], [2.5, 3.25]]
            }
        }
        """
        mktempdir() do dir
            path = write_test_segment(dir, json, extension = ".geojson")
            @test_throws ArgumentError read_segment(path)
        end
    end

    @testset "null properties attr" begin
        json = """
        {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [[1.5, 2.25], [2.5, 3.25]]
            },
            "properties": null
        }
        """
        mktempdir() do dir
            path = write_test_segment(dir, json, extension = ".geojson")
            segment = @test_logs (:warn,) read_segment(path)
            @test segment.name == ""
            @test segment.latitude == [2.25, 3.25]
            @test segment.longitude == [1.5, 2.5]
        end
    end

    @testset "rejects LineString with fewer than 2 points" begin
        json = """
        {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [[1.5, 2.25]]
            },
            "properties": {
                "name": "segment"
            }
        }
        """
        mktempdir() do dir
            path = write_test_segment(dir, json, extension = ".geojson")
            @test_throws ArgumentError read_segment(path)
        end
    end
end
