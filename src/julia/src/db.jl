using SQLite
using Dates

function create_connection!(db_path::String)::SQLite.DB
    db = SQLite.DB(db_path)
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
            matcher_version INTEGER NOT NULL
        );
        """
    )
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

function get_content_fingerprint(db::SQLite.DB, source_path::String)::String
    result = DBInterface.execute(
        db,
        "SELECT content_fingerprint from source_files WHERE source_path = ?",
        [source_path]
    )
    return only(row[:content_fingerprint] for row in result)
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
    )::Vector{String}
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
    return [row[:source_fingerprint] for row in result]
end

function select_by_time_range(
        db::SQLite.DB,
        t0::DateTime,
        t1::DateTime;
        sport::Union{String, Nothing} = nothing,
    )::Vector{String}
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
    return [row[:source_fingerprint] for row in result]
end

function select_by_id(db::SQLite.DB, activity_id::Int)::String
    result = DBInterface.execute(
        db,
        """
            SELECT source_fingerprint FROM activities
            WHERE activity_id = ?
        """,
        [activity_id]
    )
    return only(row[:source_fingerprint] for row in result)
end

function select_all(
        db::SQLite.DB; sport::Union{String, Nothing} = nothing
    )::Vector{Tuple{Int, String}}
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
    return [(row[:activity_id], row[:source_fingerprint]) for row in result]
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
        matcher_version::Int
    )::Nothing
    DBInterface.execute(
        db,
        """
            INSERT INTO segment_efforts (
                activity_id,
                segment_id,
                elapsed_time_s,
                matched_at,
                matcher_version
            ) VALUES (
                :activity_id,
                :segment_id,
                :elapsed_time_s,
                :matched_at,
                :matcher_version
            )
        """,
        Dict(
            :activity_id => activity_id,
            :segment_id => segment_id,
            :elapsed_time_s => elapsed_time_s,
            :matched_at => matched_at,
            :matcher_version => matcher_version
        )
    )
    return
end

function fetch_segment_registration(db::SQLite.DB, name::String)::NamedTuple
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments WHERE name = ?",
        [name]
    )
    segment_row = only(NamedTuple(r) for r in result)
    return segment_row
end

function fetch_segment_registration(db::SQLite.DB)::Vector{NamedTuple}
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments ORDER BY name"
    )
    return [NamedTuple(r) for r in result]
end

function fetch_segment_names(db::SQLite.DB)::Vector{String}
    result = DBInterface.execute(db, "SELECT name FROM segments ORDER BY name")
    return [r[:name] for r in result]
end

function remove_segment!(db::SQLite.DB, name::String)::Union{NamedTuple, Nothing}
    result = DBInterface.execute(
        db,
        "DELETE FROM segments WHERE name = ? RETURNING *",
        [name]
    )
    rows = [NamedTuple(r) for r in result]

    if length(rows) == 0
        return nothing
    end

    return only(rows)
end

function remove_segment!(db::SQLite.DB, segment_id::Integer)::Union{NamedTuple, Nothing}
    result = DBInterface.execute(
        db,
        "DELETE FROM segments WHERE segment_id = ? RETURNING *",
        [segment_id]
    )
    rows = [NamedTuple(r) for r in result]

    if length(rows) == 0
        return nothing
    end

    return only(rows)
end

function fetch_segment_registration_by_name(
        db::SQLite.DB, name::String
    )::Union{NamedTuple, Nothing}
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments WHERE name = ?",
        [name]
    )
    rows = [NamedTuple(r) for r in result]
    if isempty(rows)
        return nothing
    end
    return only(rows)
end

function fetch_segment_registration_by_fingerprint(
        db::SQLite.DB, fingerprint::String
    )::Union{NamedTuple, Nothing}
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments WHERE definition_fingerprint = ?",
        [fingerprint]
    )
    rows = [NamedTuple(r) for r in result]
    if isempty(rows)
        return nothing
    end
    return only(rows)
end

function fetch_segment_registration_by_path(
        db::SQLite.DB, path::String
    )::Union{NamedTuple, Nothing}
    result = DBInterface.execute(
        db,
        "SELECT * FROM segments WHERE definition_path = ?",
        [path]
    )
    rows = [NamedTuple(r) for r in result]
    if isempty(rows)
        return nothing
    end
    return only(rows)
end

function remove_segment_efforts!(db::SQLite.DB, segment_id::Integer)::Vector{NamedTuple}
    result = DBInterface.execute(
        db,
        "DELETE FROM segment_efforts WHERE segment_id = ? RETURNING *",
        [segment_id]
    )
    # TODO: Replace list comprehensions with broadcast syntax
    return [NamedTuple(r) for r in result]
end

function remove_segment_efforts!(
        db::SQLite.DB, segment_id::Integer, activity_id::Integer
    )::Vector{NamedTuple}
    result = DBInterface.execute(
        db,
        "DELETE FROM segment_efforts WHERE segment_id = ? AND activity_id = ? RETURNING *",
        [segment_id, activity_id]
    )
    # TODO: Replace list comprehensions with broadcast syntax
    return [NamedTuple(r) for r in result]
end

function fetch_segment_efforts_by_name(db::SQLite.DB, name::String)::Vector{NamedTuple}
    query = """
    SELECT
        se.effort_id,
        se.activity_id,
        CAST(a.start_time AS REAL) AS start_time,
        se.segment_id,
    	s.name,
        se.elapsed_time_s,
        se.matched_at,
        se.matcher_version
    FROM segment_efforts se
    JOIN activities a ON a.activity_id = se.activity_id
    JOIN segments s ON s.segment_id = se.segment_id
    WHERE s.name = ?
    ORDER BY elapsed_time_s;
    """
    results = DBInterface.execute(db, query, [name])
    return [NamedTuple(r) for r in results]
end
