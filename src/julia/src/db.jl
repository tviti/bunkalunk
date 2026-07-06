using SQLite
using Dates

function bunk_schema_version()
    return 20260705
end

function fetch_user_version(conn::SQLite.DB)
    result = DBInterface.execute(conn, "PRAGMA user_version;")
    user_version = Int64[r[:user_version] for r in result]
    return only(user_version)
end

struct UninitializedDatabaseError <: Exception
    message::String
end

struct SchemaVersionMismatchError <: Exception
    message::String
end

function assert_schema_valid(db::SQLite.DB)::Nothing
    user_version = fetch_user_version(db)
    user_version == 0 && throw(
        UninitializedDatabaseError(
            "Got user_version = 0, have you run `bunk` yet?"
        )
    )

    expected_user_version = bunk_schema_version()
    user_version != bunk_schema_version() && throw(
        SchemaVersionMismatchError(
            "Encountered unexpected user_version, got $user_version, " *
                "expected $expected_user_version"
        )
    )
    return
end

function create_lunk_tables!(db::SQLite.DB)::Nothing
    DBInterface.execute(
        db,
        """
        CREATE TABLE IF NOT EXISTS segments (
            segment_id INTEGER PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            definition_fingerprint TEXT NOT NULL UNIQUE,
            definition_path TEXT NOT NULL UNIQUE
        );
        """
    )
    DBInterface.execute(
        db,
        """
        CREATE TABLE IF NOT EXISTS segment_efforts (
            effort_id INTEGER PRIMARY KEY,
            activity_id INTEGER NOT NULL,
            segment_id INTEGER NOT NULL,
            elapsed_time_s REAL NOT NULL,
            matched_at INTEGER NOT NULL,
            matcher_version INTEGER NOT NULL,
            idx_start INTEGER NOT NULL,
            idx_end INTEGER NOT NULL,
            FOREIGN KEY(activity_id) REFERENCES activities(activity_id),
            FOREIGN KEY(segment_id) REFERENCES segments(segment_id)
        );
        """
    )
    return
end

function create_connection!(db_path::String)
    db = SQLite.DB(db_path)
    assert_schema_valid(db)
    DBInterface.execute(db, "PRAGMA foreign_keys = ON;")
    create_lunk_tables!(db)
    return db
end

function create_connection!(f::Function, db_path::String)
    db = create_connection!(db_path)
    try
        return f(db)
    finally
        close(db)
    end
end

function get_content_fingerprint(db::SQLite.DB, source_path::String)
    result = DBInterface.execute(
        db,
        "SELECT content_fingerprint from source_files WHERE source_path = ?",
        [source_path]
    )
    fingerprints = String[row[:content_fingerprint] for row in result]
    return only(fingerprints)
end

function add_sport_to_query(query::String, sport::Union{String, Nothing} = nothing)
    if sport !== nothing
        return query * " AND sport = :sport"
    end
    return query
end

function select_by_start_date(
        db::SQLite.DB,
        start_date::String;
        sport::Union{String, Nothing} = nothing,
    )
    t0 = DateTime(start_date, dateformat"yyyy-mm-dd")
    t0_epoch = datetime2unix(t0)
    t1_epoch = datetime2unix(t0 + Day(1))
    query = """
      SELECT source_fingerprint from activities
      WHERE start_time >= :t0_epoch
      AND start_time < :t1_epoch
    """
    query = add_sport_to_query(query, sport)
    result = DBInterface.execute(
        db,
        query,
        Dict(:t0_epoch => t0_epoch, :t1_epoch => t1_epoch, :sport => sport)
    )
    return String[row[:source_fingerprint] for row in result]
end

function select_by_time_range(
        db::SQLite.DB,
        t0::DateTime,
        t1::DateTime;
        sport::Union{String, Nothing} = nothing,
    )
    t0_epoch = datetime2unix(t0)
    t1_epoch = datetime2unix(t1)
    query = """
      SELECT source_fingerprint from activities
      WHERE start_time >= :t0_epoch
      AND start_time < :t1_epoch
    """
    query = add_sport_to_query(query, sport)
    result = DBInterface.execute(
        db,
        query,
        Dict(:t0_epoch => t0_epoch, :t1_epoch => t1_epoch, :sport => sport)
    )
    return String[row[:source_fingerprint] for row in result]
end

function select_by_id(db::SQLite.DB, activity_id::Int)
    result = DBInterface.execute(
        db,
        """
            SELECT source_fingerprint FROM activities
            WHERE activity_id = ?
        """,
        [activity_id]
    )
    fingerprints = String[row[:source_fingerprint] for row in result]
    return only(fingerprints)
end

function select_all(
        db::SQLite.DB; sport::Union{String, Nothing} = nothing
    )
    query = "SELECT activity_id, source_fingerprint FROM activities"
    if sport !== nothing
        query *= " WHERE sport = :sport"
    end
    query *= " ORDER BY start_time"
    result = DBInterface.execute(
        db,
        query,
        Dict(:sport => sport)
    )
    return Tuple{Int, String}[
        (row[:activity_id], row[:source_fingerprint]) for row in result
    ]
end

function insert_segment!(
        db::SQLite.DB,
        name::String,
        definition_path::String,
        definition_fingerprint::String
    )::Nothing
    DBInterface.execute(
        db,
        """
        INSERT INTO segments (
            name,
            definition_fingerprint,
            definition_path
        ) VALUES (
            :name,
            :definition_fingerprint,
            :definition_path
        )
        """,
        Dict(
            :name => name,
            :definition_fingerprint => definition_fingerprint,
            :definition_path => definition_path
        )
    )
    return
end

function insert_segment_effort!(
        db::SQLite.DB,
        activity_id::Int,
        segment_id::Int,
        elapsed_time_s::Real,
        matched_at::Int,
        matcher_version::Int,
        idx_start::Int,
        idx_end::Int
    )::Nothing
    DBInterface.execute(
        db,
        """
            INSERT INTO segment_efforts (
                activity_id,
                segment_id,
                elapsed_time_s,
                matched_at,
                matcher_version,
                idx_start,
                idx_end
            ) VALUES (
                :activity_id,
                :segment_id,
                :elapsed_time_s,
                :matched_at,
                :matcher_version,
                :idx_start,
                :idx_end
            )
        """,
        Dict(
            :activity_id => activity_id,
            :segment_id => segment_id,
            :elapsed_time_s => elapsed_time_s,
            :matched_at => matched_at,
            :matcher_version => matcher_version,
            :idx_start => idx_start,
            :idx_end => idx_end
        )
    )
    return
end

const SegmentRegistration = @NamedTuple{
    segment_id::Int64,
    name::String,
    definition_fingerprint::String,
    definition_path::String,
}

const SegmentEffort = @NamedTuple{
    effort_id::Int64,
    activity_id::Int64,
    segment_id::Int64,
    elapsed_time_s::Float64,
    matched_at::Int64,
    matcher_version::Int64,
    idx_start::Int64,
    idx_end::Int64,
    start_time::Union{Float64, Missing},
    name::Union{String, Nothing},
}

SegmentEffort(r::SQLite.Row) = SegmentEffort(
    (
        start_time = get(r, :start_time, missing),
        name = get(r, :name, nothing),
        effort_id = r[:effort_id],
        activity_id = r[:activity_id],
        segment_id = r[:segment_id],
        elapsed_time_s = r[:elapsed_time_s],
        matched_at = r[:matched_at],
        matcher_version = r[:matcher_version],
        idx_start = r[:idx_start],
        idx_end = r[:idx_end],
    )
)

function fetch_segment_registration(db::SQLite.DB, name::String)
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments WHERE name = ?",
        [name]
    )
    registrations = [SegmentRegistration(r) for r in result]
    return only(registrations)
end

function fetch_segment_registration(db::SQLite.DB)
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments ORDER BY segment_id"
    )
    return [SegmentRegistration(r) for r in result]
end

function fetch_segment_names(db::SQLite.DB)
    result = DBInterface.execute(db, "SELECT name FROM segments ORDER BY name")
    return String[r[:name] for r in result]
end

function remove_segment!(db::SQLite.DB, name::String)
    result = DBInterface.execute(
        db,
        "DELETE FROM segments WHERE name = ? RETURNING *",
        [name]
    )
    registrations = [SegmentRegistration(r) for r in result]

    if length(registrations) == 0
        return nothing
    end

    return only(registrations)
end

function remove_segment!(db::SQLite.DB, segment_id::Integer)
    result = DBInterface.execute(
        db,
        "DELETE FROM segments WHERE segment_id = ? RETURNING *",
        [segment_id]
    )
    registrations = [SegmentRegistration(r) for r in result]

    if length(registrations) == 0
        return nothing
    end

    return only(registrations)
end

function fetch_segment_registration_by_name(
        db::SQLite.DB, name::String
    )
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments WHERE name = ?",
        [name]
    )
    registrations = [SegmentRegistration(r) for r in result]
    if isempty(registrations)
        return nothing
    end
    return only(registrations)
end

function fetch_segment_registration_by_fingerprint(
        db::SQLite.DB, fingerprint::String
    )
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments WHERE definition_fingerprint = ?",
        [fingerprint]
    )
    registrations = [SegmentRegistration(r) for r in result]
    if isempty(registrations)
        return nothing
    end
    return only(registrations)
end

function fetch_segment_registration_by_path(
        db::SQLite.DB, path::String
    )
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments WHERE definition_path = ?",
        [path]
    )
    registrations = [SegmentRegistration(r) for r in result]
    if isempty(registrations)
        return nothing
    end
    return only(registrations)
end

function remove_segment_efforts!(db::SQLite.DB, segment_id::Integer)
    result = DBInterface.execute(
        db,
        "DELETE FROM segment_efforts WHERE segment_id = ? RETURNING *",
        [segment_id]
    )
    return [SegmentEffort(r) for r in result]
end

function remove_segment_efforts!(
        db::SQLite.DB, segment_id::Integer, activity_id::Integer
    )
    result = DBInterface.execute(
        db,
        "DELETE FROM segment_efforts WHERE segment_id = ? AND activity_id = ? RETURNING *",
        [segment_id, activity_id]
    )
    return [SegmentEffort(r) for r in result]
end

function fetch_segment_efforts_by_name(db::SQLite.DB, name::String)
    query = """
        SELECT
            se.effort_id,
            se.activity_id,
            se.segment_id,
            se.elapsed_time_s,
            se.matched_at,
            se.matcher_version,
            se.idx_start,
            se.idx_end,
            CAST(a.start_time AS REAL) AS start_time,
	    s.name AS name
        FROM segment_efforts se
        JOIN activities a ON a.activity_id = se.activity_id
        JOIN segments s ON s.segment_id = se.segment_id
        WHERE s.name = ?
        ORDER BY elapsed_time_s;
        """
    result = DBInterface.execute(db, query, [name])
    return [SegmentEffort(r) for r in result]
end
