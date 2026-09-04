using PackageCompiler

const SCRIPT_DIR = abspath(@__DIR__)
const BUILD_DIR = isempty(ARGS) ? error("usage: build.jl <build-directory>") : abspath(ARGS[1])

const SOURCE_DIR = joinpath(SCRIPT_DIR, "..", "..")
const OUT_DIR = joinpath(BUILD_DIR, "app")
const PRECOMPILE_FILE = joinpath(SCRIPT_DIR, "..", "precompile", "lunk_cli.jl")

create_app(
    SOURCE_DIR,
    OUT_DIR;
    precompile_execution_file = PRECOMPILE_FILE
)
