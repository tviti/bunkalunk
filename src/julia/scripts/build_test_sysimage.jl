using PackageCompiler
using Pkg
using SHA
using TOML

const SCRIPT_DIR = abspath(@__DIR__)
const TEST_PROJECT = joinpath(SCRIPT_DIR, "test_sysimage")
const SYSIMAGE_PATH = isempty(ARGS) ? error("usage: build_test_sysimage.jl <output-path>") : abspath(ARGS[1])
const PRECOMPILE_FILE = joinpath(SCRIPT_DIR, "precompile_execution_file.jl")
const TEST_PROJECT_TOML = joinpath(TEST_PROJECT, "Project.toml")
const TEST_MANIFEST_TOML = joinpath(TEST_PROJECT, "Manifest.toml")
const HASH_PATH = SYSIMAGE_PATH * ".sha256"

# PackageCompiler itself can't be in a sysimage it builds; TOML is a stdlib.
const SKIP = Set(["PackageCompiler", "TOML"])

mkpath(dirname(SYSIMAGE_PATH))

let current_hash = bytes2hex(sha256(vcat(
    read(TEST_PROJECT_TOML), read(TEST_MANIFEST_TOML), read(PRECOMPILE_FILE),
)))
    if isfile(HASH_PATH)
        stored_hash = strip(read(HASH_PATH, String))
        if stored_hash == current_hash
            @info "Sysimage hash unchanged; skipping build." HASH_PATH
            exit(0)
        end
    end

    # The precompile script needs `using Lunk` to work, so Lunk is a dep of
    # TEST_PROJECT (and gets baked into the sysimage).
    Pkg.activate(TEST_PROJECT)
    Pkg.instantiate()

    create_sysimage(
        [
            Symbol(n) for n in keys(TOML.parsefile(TEST_PROJECT_TOML)["deps"])
                if !(n in SKIP)
        ];
        sysimage_path = SYSIMAGE_PATH,
        project = TEST_PROJECT,
        precompile_execution_file = PRECOMPILE_FILE,
    )

    write(HASH_PATH, current_hash)
end
