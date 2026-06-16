using PackageCompiler
using Pkg
using TOML

const SCRIPT_DIR = abspath(@__DIR__)
const TEST_PROJECT = joinpath(SCRIPT_DIR, "test_sysimage")
const SYSIMAGE_PATH = joinpath(SCRIPT_DIR, "..", "test_sysimage.so")
const PRECOMPILE_FILE = joinpath(SCRIPT_DIR, "precompile_execution_file.jl")
const TEST_PROJECT_TOML = joinpath(TEST_PROJECT, "Project.toml")

# PackageCompiler itself can't be in a sysimage it builds; TOML is a stdlib.
const SKIP = Set(["PackageCompiler", "TOML"])

# The precompile script needs `using Lunk` to work, so Lunk is a dep of
# TEST_PROJECT (and gets baked into the sysimage).
Pkg.activate(TEST_PROJECT)
Pkg.instantiate()

create_sysimage(
    [Symbol(n) for n in keys(TOML.parsefile(TEST_PROJECT_TOML)["deps"])
     if !(n in SKIP)];
    sysimage_path=SYSIMAGE_PATH,
    project=TEST_PROJECT,
    precompile_execution_file=PRECOMPILE_FILE,
)
