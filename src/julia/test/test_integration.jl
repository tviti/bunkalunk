using Test
using Lunk

@testset "cache schema version guard" begin
    function compare_bunkalunk_cache_versions(cache_version = Lunk.CACHE_VERSION)
        mktempdir() do dir
            script = """
            from bunkalunk.cache import CACHE_VERSION
            assert CACHE_VERSION == $cache_version
            """
            return success(`python -c $script`)
        end
    end

    @testset "bunk matches lunk" begin
        @test compare_bunkalunk_cache_versions()
    end

    @testset "mismatches are caught" begin
        # Make sure the "bunk matches lunk" test isn't vacuous
        @test !(compare_bunkalunk_cache_versions(Lunk.CACHE_VERSION - 1))
    end
end

@testset "create_connection DB schema version guard" begin
    @testset "Happy path" begin
        mktempdir() do dir
            db_path = joinpath(dir, "db.sqlite3")
            script = """
            from bunkalunk.db import create_connection
            conn = create_connection('$db_path')
            conn.close()
            """
            process = run(`python -c $script`)
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
            from bunkalunk.db import connections
            connections.BUNK_SCHEMA_VERSION = $bad_version
            conn = connections.create_connection('$db_path')
            conn.close()
            """
            cmd = `python -c "$script"`
            process = run(cmd)
            @test isfile(db_path)
            @test_throws Lunk.SchemaVersionMismatchError create_connection!(db_path) do conn
            end
        end
    end
end
