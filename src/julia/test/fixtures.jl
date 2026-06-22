# Common fixtures
#
# If it's not used in more than one test file, it doesn't belong in here
#
using SQLite
using Lunk

if !@isdefined(BUNK_TEST_FIXTURES_INCLUDED)
    const BUNK_TEST_FIXTURES_INCLUDED = true

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
end
