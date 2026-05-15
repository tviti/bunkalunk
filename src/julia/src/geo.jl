const R_Earth::Float64 = 6371.2

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
