using HDF5

struct CacheData
    start_time::Float64
    time::Vector{Float64}
    latitude::Vector{Float64}
    longitude::Vector{Float64}
    sport::Union{String, Nothing}
    heart_rate::Union{Vector{Float64}, Nothing}
end

CacheData(start_time, time, latitude, longitude; sport = nothing, heart_rate = nothing) =
    CacheData(start_time, time, latitude, longitude, sport, heart_rate)

function _read_or_nothing(f::HDF5.File, name::String)
    return haskey(f, name) ? read(f, name) : nothing
end

function _read_or_nothing(f::HDF5.AttributeDict, name::String)
    return haskey(f, name) ? f[name] : nothing
end

function read_cache(file_path::String)::CacheData
    return h5open(file_path, "r") do file
        file_attrs = attrs(file)
        CacheData(
            file_attrs["start_time"],
            read(file, "time"),
            read(file, "latitude"),
            read(file, "longitude"),
            sport = _read_or_nothing(file_attrs, "sport"),
            heart_rate = _read_or_nothing(file, "heart_rate")
        )
    end
end
