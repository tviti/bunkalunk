using Test
using Lunk

@testset "create_connection DB schema version guard" begin
    @testset "Happy path" begin
        mktempdir() do dir
            db_path = joinpath(dir, "db.sqlite3")
            cmd = `python -c "from bunkalunk import db; conn = db.create_connection('$db_path'); conn.close()"`
            process = run(cmd)
            @test process.exitcode == 0
            @test isfile(db_path)
            create_connection!(db_path) do conn
            end
        end
    end

    @testset "throws on uninitialized" begin
        mktempdir() do dir
            @test_throws Lunk.UninitializedDatabaseError create_connection!(joinpath(dir, "db.sqlite3"))
        end
    end

    @testset "throws on mismatch" begin
        mktempdir() do dir
            db_path = joinpath(dir, "db.sqlite3")
            bad_version = Lunk.bunk_schema_version() - 1
            script = """
            from bunkalunk import db
            db.BUNK_SCHEMA_VERSION = $bad_version
            conn = db.create_connection('$db_path')
            conn.close()
            """
            cmd = `python -c "$script"`
            process = run(cmd)
            @test process.exitcode == 0
            @test isfile(db_path)
            @test_throws Lunk.SchemaVersionMismatchError create_connection!(db_path) do conn
            end
        end
    end
end
