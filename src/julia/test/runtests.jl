using Test
using Lunk

@testset "Lunk" begin
    include("test_cache.jl")
    include("test_db.jl")
    include("test_osm.jl")
end
