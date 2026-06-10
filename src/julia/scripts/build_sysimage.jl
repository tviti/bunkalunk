using PackageCompiler
using TOML

const SCRIPT_DIR = abspath(@__DIR__)
const SCRIPT_PROJECT = joinpath(SCRIPT_DIR, "Project.toml")
const SYSIMAGE_PATH = joinpath(SCRIPT_DIR, "..", "dev_sysimage.so")

# PackageCompiler itself can't be in a sysimage it builds; TOML is a stdlib.
const SKIP = Set(["PackageCompiler", "TOML"])

create_sysimage(
    [Symbol(n) for n in keys(TOML.parsefile(SCRIPT_PROJECT)["deps"])
     if !(n in SKIP)];
    sysimage_path=SYSIMAGE_PATH,
    project=SCRIPT_DIR,
)
