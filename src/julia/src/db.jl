using SQLite

include("paths.jl")

const _SUFFIX = ".h5"


function create_connection(db_path::String)::SQLite.DB
    SQLite.DB(db_path)
end


function get_content_fingerprint(db::SQLite.DB, source_path::String)::String
    result = DBInterface.execute(
        db,
        "SELECT content_fingerprint from source_files WHERE source_path = ?",
        [source_path]
    )
    only(row[:content_fingerprint] for row in result)
end


function select_by_start_date(db::SQLite.DB, start_date::String)::Vector{String}
    result = DBInterface.execute(
        db,
        "SELECT source_fingerprint from activities
          WHERE start_time >= date(:start_date)
            AND start_time < date(:start_date, '+1 day')",
        Dict(:start_date => start_date)
    )
    [row[:source_fingerprint] for row in result]
end


function select_by_time_range(db::SQLite.DB, t0::String, t1::String)::Vector{String}
    result = DBInterface.execute(
        db,
        "SELECT source_fingerprint from activities
          WHERE start_time >= :start_time
            AND start_time < :end_time",
        Dict(:start_time => t0,
             :end_time => t1)
    )
    [row[:source_fingerprint] for row in result]
end
