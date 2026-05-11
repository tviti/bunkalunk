"""
    BUNK_HOME, ACTIVITY_STORE

Globals for the bunk data directories.
"""
const BUNK_HOME = get(ENV, "BUNK_HOME", joinpath(homedir(), ".bunk"))
const ACTIVITY_STORE = joinpath(BUNK_HOME, "activity_store")
