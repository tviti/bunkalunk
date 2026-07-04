using HDF5

struct CacheData
    start_time::Float64
    time::Vector{Float64}
    latitude::Vector{Float64}
    longitude::Vector{Float64}
    sport::Union{String, Nothing}
    heart_rate::Union{Vector{Float64}, Nothing}
    elevation::Union{Vector{Float64}, Nothing}
    distance::Union{Vector{Float64}, Nothing}
    speed::Union{Vector{Float64}, Nothing}
end

const _CACHE_FIELDS_OPTIONAL = [
    fname for (fname, ftype) in zip(fieldnames(CacheData), fieldtypes(CacheData))
        if Nothing <: ftype
]

const _CACHE_FIELDS_OPTIONAL_SCALAR = [:sport]
const _CACHE_FIELDS_OPTIONAL_VECTOR = setdiff(
    _CACHE_FIELDS_OPTIONAL, _CACHE_FIELDS_OPTIONAL_SCALAR
)

CacheData(
    start_time,
    time,
    latitude,
    longitude
    ;
    sport = nothing,
    heart_rate = nothing,
    elevation = nothing,
    distance = nothing,
    speed = nothing
) = CacheData(
    start_time,
    time,
    latitude,
    longitude,
    sport,
    heart_rate,
    elevation,
    distance,
    speed
)

function _read_or_nothing(f::HDF5.File, name::String)
    return haskey(f, name) ? read(f, name) : nothing
end

function _read_or_nothing(f::HDF5.AttributeDict, name::String)
    return haskey(f, name) ? f[name] : nothing
end

function read_cache(file_path::String)
    return h5open(file_path, "r") do file
        file_attrs = attrs(file)
        CacheData(
            file_attrs["start_time"],
            read(file, "time"),
            read(file, "latitude"),
            read(file, "longitude")
            ;
            sport = _read_or_nothing(file_attrs, "sport"),
            heart_rate = _read_or_nothing(file, "heart_rate"),
            elevation = _read_or_nothing(file, "elevation"),
            speed = _read_or_nothing(file, "speed"),
            distance = _read_or_nothing(file, "distance")
        )
    end
end


"""
    drop_invalid_gps_points(cache::CacheData)::CacheData

Drop rows with invalid GPS coordinates from a `CacheData` object while
preserving row alignment across fields.

Garmin FIT files may contain track records with `NaN` latitude and longitude
values if recording began before GPS lock was acquired. This function removes
those records from the decoded data.

Only rows with both `latitude` and `longitude` present and non-`NaN` are kept.
"""
function drop_invalid_gps_points(cache::CacheData)
    valid = @. !isnan(cache.latitude) & !isnan(cache.longitude)

    vector_kwargs = Dict()
    for field_name in _CACHE_FIELDS_OPTIONAL_VECTOR
        field_value = getfield(cache, field_name)
        if field_value !== nothing
            vector_kwargs[field_name] = field_value[valid]
        end
    end

    return CacheData(
        cache.start_time,
        cache.time[valid],
        cache.latitude[valid],
        cache.longitude[valid]
        ;
        sport = cache.sport,
        vector_kwargs...
    )
end
