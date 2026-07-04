using Dates
using Printf
using DelimitedFiles


# GeoCSV standard types for CSVT sidecar file
csvt_type(::Type{Int32}) = "Integer"
csvt_type(::Type{Int64}) = "Integer64"
csvt_type(::Type{<:Real}) = "Real"
csvt_type(::Type{String}) = "String"
csvt_type(::Type{Dates.Date}) = "Date"
csvt_type(::Type{Dates.Time}) = "Time"
csvt_type(::Type{Dates.DateTime}) = "DateTime"

csvt_type(T::Type) = throw(ArgumentError("No CSVT mapping for $T"))

struct GeoCSV
    x::Vector{Float64}
    y::Vector{Float64}
    time::Vector{DateTime}
    fields::Union{Vector{<:AbstractVector}, Nothing}
    field_names::Union{Vector{String}, Nothing}
end

function write_geocsv!(path::String, coords::GeoCSV; kwargs...)::Nothing
    return write_geocsv!(
        path,
        coords.x,
        coords.y,
        coords.time;
        fields = coords.fields,
        field_names = coords.field_names,
        kwargs...
    )
end

"""
    write_geocsv!(
        path::String,
        x::Vector{<:Real},
        y::Vector{<:Real},
        time::Vector{DateTime},
        ;
        fields::Union{Vector{<:AbstractVector}, Nothing} = nothing,
        field_names::Union{Vector{String}, Nothing} = nothing,
        x_name::String = "Longitude",
        y_name::String = "Latitude",
        time_name::String = "timestamp",
        write_sidecar::Bool = true
    )::Nothing

Write a GeoCSV formatted CSV file.

This function is designed to create files that are ready for consumption by
GDAL. The `time` input is assumed to be in UTC. Since the stdlib `DateTime`
object is timezone naive, callers must be wary of silently violating this. For
example, the following will pass through undetected and then be interpreted by
the file consumers incorrectly as a UTC timestamp:
  `time = Dates.now() # LOCAL time, use Dates.now(Dates.UTC) instead`

When `write_sidecar` is set (default `true`), also writes a .csvt sidecar file
with the column types. Callers are responsible for ensuring the input vectors
are aligned.

Raises `ArgumentError` if:
- `x`, `y`, `time`, or the individual elements of `fields`, are not all the same length
- `fields` and `field_names` are not the same length
- `fields` is set but `field_names` is `nothing`
- any written column name contains a comma

See also:
- https://www.giswiki.ch/GeoCSV
- https://gdal.org/en/stable/drivers/vector/csv.html
"""
function write_geocsv!(
        path::String,
        x::Vector{<:Real},
        y::Vector{<:Real},
        time::Vector{DateTime};
        fields::Union{Vector{<:AbstractVector}, Nothing} = nothing,
        field_names::Union{Vector{String}, Nothing} = nothing,
        x_name::String = "Longitude",
        y_name::String = "Latitude",
        time_name::String = "timestamp",
        write_sidecar::Bool = true
    )::Nothing
    base_path, ext = splitext(path)
    ext == ".csv" || throw(
        ArgumentError(
            "Unrecognized file extension, got $ext"
        )
    )

    num_x = length(x)
    num_y = length(y)
    num_time = length(time)
    num_x == num_y && num_y == num_time || throw(
        ArgumentError(
            "x, y, time have unequal lengths, got $num_x, $num_y, $num_time"
        )
    )

    fields === nothing || field_names !== nothing || throw(
        ArgumentError(
            "Got fields but no field_names"
        )
    )

    if fields !== nothing
        num_fields = length(fields)
        num_field_names = length(field_names)
        num_fields == num_field_names || throw(
            ArgumentError(
                "fields and field_names are unequal length, got $num_fields, $num_field_names"
            )
        )

        field_lengths = length.(fields)
        length(unique(field_lengths)) == 1 || throw(
            ArgumentError(
                "Unequal length field vectors, got $field_lengths"
            )
        )

        first(field_lengths) == num_y || throw(
            ArgumentError(
                "Field length does not match coordinate length, got $first(field_lengths), $num_y"
            )
        )
    end

    time_formatted = Dates.format.(time, "YYYY-mm-ddTHH:MM:SS.sssZ")
    data_out = [x y time_formatted]
    header = [x_name, y_name, time_name]
    types = eltype.([x, y, time])

    if fields !== nothing
        data_out = hcat(data_out, fields...)
        header = vcat(header, field_names)
        types = [types; eltype.(f for f in fields)]
    end

    invalid_name = findfirst(name -> occursin(',', name), header)
    invalid_name === nothing || throw(
        ArgumentError(
            "Column names must not contain commas, got $(repr(header[invalid_name]))"
        )
    )

    open(path, "w") do f
        write_csv!(f, header, data_out)
    end

    if write_sidecar
        open(base_path * ".csvt", "w") do f
            write_csvt!(f, types)
        end
    end

    return
end

function write_csv!(io::IO, header::Vector{String}, data::AbstractMatrix)::Nothing
    header_fmt = Printf.Format(repeat("%s,", length(header) - 1) * "%s\n")
    Printf.format(io, header_fmt, header...)
    writedlm(io, data, ',')
    return
end


function write_csvt!(io::IO, types::Vector{<:Type})::Nothing
    csvt_format = Printf.Format(repeat("\"%s\",", length(types) - 1) * "\"%s\"\n")
    Printf.format(io, csvt_format, csvt_type.(types)...)
    return
end
