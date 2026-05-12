using SQLite
using Dates


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
    t0 = DateTime(start_date, dateformat"yyyy-mm-dd")
    t0_epoch = datetime2unix(t0)
    t1_epoch = datetime2unix(t0 + Day(1))
    result = DBInterface.execute(
        db,
        "SELECT source_fingerprint from activities
          WHERE start_time >= :t0_epoch
            AND start_time < :t1_epoch",
        Dict(:t0_epoch => t0_epoch, :t1_epoch => t1_epoch)
    )
    [row[:source_fingerprint] for row in result]
end


function select_by_time_range(db::SQLite.DB, t0::DateTime, t1::DateTime)::Vector{String}
    t0_epoch = datetime2unix(t0)
    t1_epoch = datetime2unix(t1)
    result = DBInterface.execute(
        db,
        "SELECT source_fingerprint from activities
          WHERE start_time >= :t0_epoch
            AND start_time < :t1_epoch",
        Dict(:t0_epoch => t0_epoch, :t1_epoch => t1_epoch)
    )
    [row[:source_fingerprint] for row in result]
end
