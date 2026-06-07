"""
Resources:
  - https://archive.psas.pdx.edu/CoordinateSystem/Latitude_to_LocalTangent.pdf
"""

using Statistics
using LinearAlgebra

const R_Earth::Float64 = 6371.2e3

struct Ellipsoid
    semimajor_axis::Float64
    semiminor_axis::Float64
    flatness::Float64
    eccentricity::Float64
end

"""Constructor returning an `Ellipsoid` based on EPSG:7030 (i.e. the ellipsoid
reference used by geodetic coordinates in EPSG:4326)
"""
function WGS84()::Ellipsoid
    semimajor_axis = 6378137.0
    semiminor_axis = 6356752.314245
    flatness = 1.0 - semiminor_axis / semimajor_axis
    eccentricity = sqrt(flatness * (2 - flatness))
    return Ellipsoid(semimajor_axis, semiminor_axis, flatness, eccentricity)
end

function normal_distance(lat::Real, ellipsoid::Ellipsoid)::Real
    return ellipsoid.semimajor_axis / sqrt(1 - ellipsoid.eccentricity^2 * sind(lat)^2)
end

"""
    compute_ecef_r(lat::Real, lon::Real, h::Real, ellipsoid::Ellipsoid) -> Tuple{Real, Real, Real}
    compute_ecef_r(lat::Real, lon::Real, h::Real) -> Tuple{Real, Real, Real}

Convert a set of geodetic coordinates to a rectangular ECEF frame, with `z`
aligned with the poles, `x` orthogonal to the prime meridian, and the
cross product of `x` and `y` bases yielding `z`.

If `ellipsoid` is omitted, defaults to using `WGS84()`.
"""
function compute_ecef_r(
        lat::Real,
        lon::Real,
        h::Real,
        ellipsoid::Ellipsoid
    )::Tuple{Real, Real, Real}
    N = normal_distance(lat, ellipsoid)
    cos_lat = cosd(lat)
    x = (h + N) * cos_lat * cosd(lon)
    y = (h + N) * cos_lat * sind(lon)
    z = (h + (1 - ellipsoid.eccentricity^2) * N) * sind(lat)
    return (x, y, z)
end

function compute_ecef_r(
        lat::Real,
        lon::Real,
        h::Real
    )::Tuple{Real, Real, Real}
    return compute_ecef_r(lat, lon, h, WGS84())
end

"""
    crosses_gate(
        s_0::Vector{<:Real},
        l::Vector{<:Real},
        p_1::Vector{<:Real},
        p_2::Vector{<:Real},
        tape_radius::Real
    )::Union{NamedTuple, Nothing}

Determine if the edge defined by points `p_1` and `p_2` crosses the *gate*
defined by a point `s_0`, its normal vector `l`, and its width
`tape_radius`. Gates are directional, and an affirmative crossing requires that
the edge be oriented along `l`.

If the edge does cross the gate, returns a `NamedTuple` with the interpolation
parameter `t` and the intersection point `p`. Returns `nothing` otherwise.
"""
function crosses_gate(
        s_0::Vector{<:Real}, l::Vector{<:Real},
        p_1::Vector{<:Real}, p_2::Vector{<:Real},
        tape_radius::Real,
    )::Union{NamedTuple, Nothing}
    if (p_2 - s_0) ⋅ l > 0 && (p_1 - s_0) ⋅ l < 0
        num = (s_0 - p_1) ⋅ l
        den = (p_2 - p_1) ⋅ l
        t = num / den
        if 0 <= t && t <= 1
            p = (1 - t) * p_1 + t * p_2
            if norm(p - s_0) < tape_radius
                return (t = t, p = p)
            end
        end
    end
    return nothing
end

"""
    on_polyline(p::Vector{<:Real}, polyline::Matrix{<:Real}, radius::Real)::Bool

Check if a given point `p` falls within the cylindrical coridoor defined by
`polyline` and `radius`, where `polyline` is a 3xN matrix of vertices.

Returns `true` when `p` is within `radius` of any `polyline` edges. Returns
`false` otherwise.
"""
function on_polyline(p::Vector{<:Real}, polyline::Matrix{<:Real}, radius::Real)::Bool
    num_seg = size(polyline, 2)
    for n in 1:(num_seg - 1)
        s_1 = polyline[:, n]
        s_2 = polyline[:, n + 1]
        b = norm(p - s_1)
        if b < radius
            return true
        end
        s = s_2 - s_1
        norm_s = norm(s)

        a = (p - s_1) ⋅ s / norm_s
        0 < a && a <= norm_s || continue

        c = sqrt(b^2 - a^2)
        if c < radius
            return true
        end
    end

    return false
end

function linterp(q_1, q_2, t)
    return (1 - t) * q_1 + t * q_2
end

function haversine_distance(p₁::Tuple{Float64, Float64}, p₂::Tuple{Float64, Float64})::Float64
    # p1 and p2 are tuples of (lat, lon) in degrees
    Δϕ = p₂[1] - p₁[1]
    Δλ = p₂[2] - p₁[2]
    havθ = 0.5 * (1 - cosd(Δϕ) + cosd(p₁[1]) * cosd(p₂[1]) * (1 - cosd(Δλ)))
    (0 <= havθ && havθ <= 1) ||
        throw(DomainError("Function requires 0 <= hav(θ) <= 1 but got $havθ"))
    θ = 2 * asin(sqrt(havθ))
    return R_Earth * θ
end
