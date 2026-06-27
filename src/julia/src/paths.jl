"""
    BUNK_HOME, ACTIVITY_STORE

Globals for the bunk data directories.
"""
const _CACHE_SUFFIX = ".h5"

function resolve_bunk_home()::String
    return get(ENV, "BUNK_HOME", joinpath(homedir(), ".bunk"))
end

function resolve_activity_store()::String
    return joinpath(resolve_bunk_home(), "activity_store")
end

function resolve_cache_path(content_fingerprint::String, activity_store::String)::String
    shard = content_fingerprint[1:2]
    cache_parent = joinpath(activity_store, shard)
    return cache_parent * "/" * content_fingerprint * _CACHE_SUFFIX
end

function resolve_cache_path(content_fingerprint::String)::String
    return resolve_cache_path(content_fingerprint, resolve_activity_store())
end
