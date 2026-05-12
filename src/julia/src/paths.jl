"""
    BUNK_HOME, ACTIVITY_STORE

Globals for the bunk data directories.
"""
const BUNK_HOME = get(ENV, "BUNK_HOME", joinpath(homedir(), ".bunk"))
const ACTIVITY_STORE = joinpath(BUNK_HOME, "activity_store")
const _CACHE_SUFFIX = ".h5"


function resolve_cache_path(content_fingerprint::String, activity_store::String)::String
    shard = content_fingerprint[1:2]
    cache_parent = joinpath(activity_store, shard)
    return cache_parent * "/" * content_fingerprint * _CACHE_SUFFIX
end
