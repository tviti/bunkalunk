using SQLite
using Dates

function create_connection(db_path::String)::SQLite.DB
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
            matcher_version INTEGER NOT NULL,
            UNIQUE(activity_id, segment_id)
        );
        """
    )
    return db
end

function create_connection(f::Function, db_path::String)
    db = create_connection(db_path)
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

function upsert_segment(
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
        ) ON CONFLICT(name) DO UPDATE SET
            definition_fingerprint=excluded.definition_fingerprint,
            definition_path=excluded.definition_path
        """,
        Dict(
            :name => name,
            :definition_fingerprint => definition_fingerprint,
            :definition_path => definition_path
        )
    )
    return
end

function upsert_segment_effort(
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
            ) ON CONFLICT(activity_id, segment_id) DO UPDATE SET
                elapsed_time_s = excluded.elapsed_time_s,
                matched_at = excluded.matched_at,
                matcher_version = excluded.matcher_version
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

function remove_segment(db::SQLite.DB, name::String)::Union{NamedTuple, Nothing}
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

function remove_segment_efforts(db::SQLite.DB, segment_id::Integer)::Vector{NamedTuple}
    result = DBInterface.execute(
        db,
        "DELETE FROM segment_efforts WHERE segment_id = ? RETURNING *",
        [segment_id]
    )
    # TODO: Replace list comprehensions with broadcast syntax
    return [NamedTuple(r) for r in result]
end
