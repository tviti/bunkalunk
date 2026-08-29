# Common fixtures
#
# If it's not used in more than one test file, it doesn't belong in here
#
using SQLite
using Lunk
using Dates
using HDF5
using DelimitedFiles

if !@isdefined(BUNK_TEST_FIXTURES_INCLUDED)
    const BUNK_TEST_FIXTURES_INCLUDED = true

    # Cache fixtures
    function make_cache_lap_then_abort()::CacheData
        affirmative = CacheData(
            946598400.0,
            [0.0, 10.0, 20.0, 30.0],
            [-0.00005, 0.00005, 0.00015, 0.00025],
            [0.0, 0.0, 0.0, 0.0],
            sport = "cycling",
            heart_rate = nothing
        )
        abort = CacheData(
            946598400.0,
            [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0],
            [-0.00005, 0.00005, 0.00015, 0.00015, -0.00005, 0.00005, 0.00015, 0.00025],
            [0.0, 0.0, 0.0, 0.0003, 0.0, 0.0, 0.0, 0.0],
            sport = "cycling",
            heart_rate = nothing
        )
        lat = [affirmative.latitude; abort.latitude]
        lon = [affirmative.longitude; abort.longitude]

        # Set a different velocity for the second coordinate set so the segment
        # times are distinguishable
        N = length(affirmative.latitude)
        M = length(abort.longitude)
        time = [
            10.0 * [i for i in 1:N];
            10.0 * N .+ 20.0 * [i for i in 1:M]
        ]
        return CacheData(
            946598400.0, time, lat, lon, sport = "cycling", heart_rate = nothing
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

    function make_synthetic_segment()::Segment
        return Segment(
            "synthetic segment",
            [0.0, 0.0001, 0.0002],
            [0.0, 0.0, 0.0]
        )
    end

    function make_cache_file(
            dir
            ;
            filename = "cache",
            cache_version = Lunk.CACHE_VERSION,
            start_time = 946598400.0,
            sport::Union{String, Nothing} = "basket-weaving",
            time = Float64[0.0, 0.1, 0.2],
            latitude = Float64[1.0, 1.1, 1.2],
            longitude = Float64[2.0, 2.1, 2.2],
            heart_rate::Union{AbstractVector{<:Real}, Nothing} = Float64[99.0, 99.0, 99.0],
            elevation::Union{AbstractVector{<:Real}, Nothing} = Float64[10.0, 11.0, 12.0],
            distance::Union{AbstractVector{<:Real}, Nothing} = Float64[0.0, 1.0, 2.0],
            speed::Union{AbstractVector{<:Real}, Nothing} = Float64[3.0, 3.1, 3.2]
        )

        path = joinpath(dir, filename * ".h5")
        h5open(path, "w") do file
            file["time"] = time
            file["latitude"] = latitude
            file["longitude"] = longitude
            heart_rate !== nothing && (file["heart_rate"] = heart_rate)
            elevation !== nothing && (file["elevation"] = elevation)
            distance !== nothing && (file["distance"] = distance)
            speed !== nothing && (file["speed"] = speed)
            attributes(file)["cache_version"] = cache_version
            attributes(file)["start_time"] = start_time
            sport !== nothing && (attributes(file)["sport"] = sport)
        end
        return path
    end

    function make_registered_cache_file!(
            conn,
            dir;
            fingerprint = "cache",
            start_time = 946598400.0,
            sport::Union{String, Nothing} = "cycling",
            time = Float64[0.0, 0.1, 0.2],
            latitude = Float64[1.0, 1.1, 1.2],
            longitude = Float64[2.0, 2.1, 2.2],
            heart_rate::Union{AbstractVector{<:Real}, Nothing} = Float64[99.0, 99.0, 99.0],
            elevation::Union{AbstractVector{<:Real}, Nothing} = Float64[10.0, 11.0, 12.0],
            distance::Union{AbstractVector{<:Real}, Nothing} = Float64[0.0, 1.0, 2.0],
            speed::Union{AbstractVector{<:Real}, Nothing} = Float64[3.0, 3.1, 3.2],
            x_min = 2.0,
            x_max = 2.2,
            y_min = 1.0,
            y_max = 1.2
        )
        insert_activity!(
            conn,
            Dict(
                :source_fingerprint => fingerprint,
                :start_time => start_time,
                :ride_tag => nothing,
                :sport => sport,
                :cache_version => 20260624,
                :x_min => x_min,
                :x_max => x_max,
                :y_min => y_min,
                :y_max => y_max
            )
        )
        cache_dir = joinpath(dir, fingerprint[1:2])
        mkpath(cache_dir)
        return make_cache_file(
            cache_dir
            ;
            filename = fingerprint,
            start_time = start_time,
            sport = sport,
            time = time,
            latitude = latitude,
            longitude = longitude,
            heart_rate = heart_rate,
            elevation = elevation,
            distance = distance,
            speed = speed
        )
    end

    # Database fixtures
    function create_bunk_tables!(db_path::String)
        script = """
        from bunkalunk.db import create_connection
        with create_connection("$db_path") as conn:
            pass
        """
        cmd = `python -c $script`
        run(cmd)
        return
    end

    function with_tmp_bunk_db!(f::Function)
        return mktempdir() do dir
            db_path = joinpath(dir, "tmp.sqlite3")
            create_bunk_tables!(db_path)
            f(dir, db_path)
        end
    end

    function insert_activity!(conn::SQLite.DB, activity::Dict)::Nothing
        DBInterface.execute(
            conn,
            """
            INSERT INTO activities (
                   start_time,
                   source_fingerprint,
                   ride_tag,
                   sport,
                   cache_version,
                   x_min,
                   x_max,
                   y_min,
                   y_max
            ) VALUES (
                   :start_time,
                   :source_fingerprint,
                   :ride_tag,
                   :sport,
                   :cache_version,
                   :x_min,
                   :x_max,
                   :y_min,
                   :y_max
            )
            """,
            activity
        )
        return
    end

    function insert_dummy_activity!(
            conn::SQLite.DB, fingerprint::String; sport::Union{String, Nothing} = "cycling"
        )::Nothing
        insert_activity!(
            conn, Dict(
                :start_time => 99.999,
                :source_fingerprint => fingerprint,
                :ride_tag => nothing,
                :sport => sport,
                :cache_version => 123456,
                :x_min => 0.0,
                :x_max => 1.0,
                :y_min => 0.1,
                :y_max => 1.1
            )
        )
        return
    end

    function seed_segments_table!(db::SQLite.DB)::Nothing
        DBInterface.execute(
            db,
            """
                INSERT INTO segments (
                    name,
                    definition_fingerprint,
                    definition_path,
                    x_min,
                    x_max,
                    y_min,
                    y_max
                ) VALUES
                    ("c", "fingerprint-c", "path/to/c", 0.0, 0.1, 1.0, 1.1),
                    ("b", "fingerprint-b", "path/to/b", 0.0, 0.1, 1.0, 1.1),
                    ("a", "fingerprint-a", "path/to/a", 0.0, 0.1, 1.0, 1.1);
            """
        )
        return
    end

    function seed_segment_efforts_table!(db::SQLite.DB)::Nothing
        insert_dummy_activity!(db, "fingerprint-1")
        insert_dummy_activity!(db, "fingerprint-2")
        insert_dummy_activity!(db, "fingerprint-3"; sport = "basket-weaving")
        insert_dummy_activity!(db, "fingerprint-4")
        seed_segments_table!(db)
        DBInterface.execute(
            db,
            """
                INSERT INTO segment_efforts (activity_id,
                                             segment_id,
                                             elapsed_time_s,
                                             matched_at,
                                             matcher_version,
                                             idx_start,
                                             idx_end)
                VALUES
                    (1, 3, 100.0, 1234, $(Lunk.MATCHER_VERSION), 1, 2),
                    (2, 2, 101.1, 1235, $(Lunk.MATCHER_VERSION), 3, 4),
                    (3, 2, 102.2, 1236, $(Lunk.MATCHER_VERSION), 5, 6),
                    (4, 1, 103.3, 1237, $(Lunk.MATCHER_VERSION), 7, 8);
            """
        )
        return
    end

    # Segment fixtures
    function make_dummy_segment()
        return Segment(
            "segment-name-field",
            Float64[0.0, 0.1, 0.2, 0.3, 0.4],
            Float64[1.0, 1.1, 1.2, 1.3, 1.4],
        )
    end

    function write_minimal_osm(
            path::AbstractString;
            name::Union{String, Nothing} = "segment",
            latitude::AbstractVector{<:Real} = [0.0, 0.0001, 0.0002],
            longitude::AbstractVector{<:Real} = [0.0, 0.0, 0.0]
        )
        length(latitude) == length(longitude) || throw(
            ArgumentError("latitude and longitude must have the same length")
        )
        length(latitude) >= 2 || throw(
            ArgumentError("minimal OSM fixture requires at least two points")
        )

        # Minimal valid file: one way, N nodes, nd refs match. Changing the
        # name kwarg is an easy way to change the file contents and fingerprint.
        xml = "<osm>\n"
        for (i, (lat, lon)) in enumerate(zip(latitude, longitude))
            xml *= "    <node id=\"$i\" visible=\"true\" lat=\"$lat\" lon=\"$lon\" />\n"
        end
        xml *= "    <way id=\"1\" visible=\"true\">\n"
        for i in eachindex(latitude)
            xml *= "        <nd ref=\"$i\" />\n"
        end
        if name !== nothing
            xml *= """<tag k="name" v="$name" />"""
        end
        xml *= "\n    </way>\n</osm>\n"
        return write(path, xml)
    end

    # File fixtures
    function load_csv(path::AbstractString)
        return open(path, "r") do source
            data, header = readdlm(source, ',', header = true)
            return data, strip.(header)
        end
    end

    # Context fixtures
    """
    Create a testing `Context` object that points to a DB that has been seeded
    with `bunk` tables and the right schema version.
    """
    function make_context(dir::String; io::IO = IOBuffer())
        db_path = dir * "/db.sqlite3"
        activity_store_path = dir
        verbose = false

        user_version = Lunk.bunk_schema_version()
        create_bunk_tables!(db_path)
        # conn = SQLite.DB(db_path)
        # DBInterface.execute(conn, "PRAGMA user_version = $user_version")
        # close(conn)

        return Lunk.Context(db_path, activity_store_path, verbose, io)
    end

    function with_tempdir_context(f::Function; io::IO = IOBuffer())
        return mktempdir() do dir
            cd(dir) do
                ctx = make_context(dir; io = io)
                f(ctx, dir)
            end
        end
    end

end
