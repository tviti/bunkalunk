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

    function create_activities_table!(conn::SQLite.DB)::Nothing
        DBInterface.execute(
            conn,
            """
            CREATE TABLE IF NOT EXISTS activities (
                activity_id INTEGER PRIMARY KEY,
                source_fingerprint TEXT UNIQUE NOT NULL,
                start_time REAL,
                cache_version INT,
                ride_tag TEXT,
                sport TEXT
            )
            """
        )
        return
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
                   cache_version
            ) VALUES (
                   :start_time,
                   :source_fingerprint,
                   :ride_tag,
                   :sport,
                   :cache_version
            )
            """,
            activity
        )
        return
    end

    function seed_segment_efforts_table!(db::SQLite.DB)::Nothing
        DBInterface.execute(
            db,
            """
                INSERT INTO segment_efforts (activity_id,
                                             segment_id,
                                             elapsed_time_s,
                                             matched_at,
                                             matcher_version)
                VALUES
                    (1, 3, 100.0, 1234, 20260607),
                    (2, 2, 101.1, 1235, 20260607),
                    (100, 2, 102.2, 1236, 20260607),
                    (110, 1, 103.3, 1237, 20260607);
            """
        )
        return
    end

    function seed_segments_table!(db::SQLite.DB)::Nothing
        DBInterface.execute(
            db,
            """
                INSERT INTO segments (name, definition_fingerprint, definition_path)
                VALUES
                    ("c", "fingerprint-c", "path/to/c"),
                    ("b", "fingerprint-b", "path/to/b"),
                    ("a", "fingerprint-a", "path/to/a");
            """
        )
        return
    end

    function load_csv(path::AbstractString)
        return open(path, "r") do source
            data, header = readdlm(source, ',', header = true)
            return data, strip.(header)
        end
    end

    function make_cache_file(
            dir
            ;
            filename = "cache",
            start_time = 946598400.0,
            sport = "basket-weaving"
        )
        time = [0.0, 0.1, 0.2]
        latitude = [1.0, 1.1, 1.2]
        longitude = [2.0, 2.1, 2.2]
        heart_rate = [99.0, 99.0, 99.0]

        path = joinpath(dir, filename * ".h5")
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

    function make_registered_cache_file!(conn, dir; fingerprint = "cache")
        start_time = 946598400.0
        sport = "cycling"
        insert_activity!(
            conn,
            Dict(
                :source_fingerprint => fingerprint,
                :start_time => start_time,
                :ride_tag => nothing,
                :sport => sport,
                :cache_version => 20260624,
            )
        )
        cache_dir = joinpath(dir, fingerprint[1:2])
        mkpath(cache_dir)
        return make_cache_file(
            cache_dir
            ;
            filename = fingerprint,
            start_time = start_time,
            sport = sport
        )
    end

    function make_context(dir::String; io::IO = IOBuffer())
        db_path = dir * "/db.sqlite3"
        activity_store_path = dir
        verbose = false
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
