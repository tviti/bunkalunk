using PackageCompiler
using Pkg
using SHA
using TOML

const SCRIPT_DIR = abspath(@__DIR__)
const SCRIPT_PROJECT = joinpath(SCRIPT_DIR, "Project.toml")
const MANIFEST_TOML = joinpath(SCRIPT_DIR, "Manifest.toml")
const SYSIMAGE_PATH = isempty(ARGS) ? error("usage: build.jl <output-path>") : abspath(ARGS[1])
const HASH_PATH = SYSIMAGE_PATH * ".sha256"

# PackageCompiler itself can't be in a sysimage it builds; TOML is a stdlib.
const SKIP = Set(["PackageCompiler", "TOML"])

mkpath(dirname(SYSIMAGE_PATH))

let current_hash = bytes2hex(sha256(vcat(
    read(SCRIPT_PROJECT), read(MANIFEST_TOML),
)))
    if isfile(HASH_PATH)
        stored_hash = strip(read(HASH_PATH, String))
        if stored_hash == current_hash
            @info "Sysimage hash unchanged; skipping build." HASH_PATH
            exit(0)
        end
    end

    Pkg.activate(SCRIPT_PROJECT)
    Pkg.instantiate()

    create_sysimage(
        [Symbol(n) for n in keys(TOML.parsefile(SCRIPT_PROJECT)["deps"])
         if !(n in SKIP)];
        sysimage_path=SYSIMAGE_PATH,
        project=SCRIPT_DIR,
    )

    write(HASH_PATH, current_hash)
end
