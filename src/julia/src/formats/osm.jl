using XML
import XML: attributes


struct Segment
    name::String
    latitude::Vector{Float64}
    longitude::Vector{Float64}
end


function read_segment(path::String)::Segment
    doc = XML.read(path, Node)
    root = doc[end]
    tag(root) == "osm" || throw(
        ArgumentError(
            "Root node's tag is not 'osm', got $(tag(root))"
        )
    )

    nodes = filter(x -> tag(x) == "node", children(root))
    N_nodes = length(nodes)
    N_nodes > 0 || throw(
        ArgumentError(
            "Segment file $path contains no nodes."
        )
    )

    ways = filter(x -> tag(x) == "way", children(root))
    N_ways = length(ways)
    N_ways == 1 || throw(
        ArgumentError(
            "Segment file $path must contain exactly one way, got $N_ways"
        )
    )

    way_children = children(ways[1])
    nd = filter(x -> tag(x) == "nd", way_children)
    N_nd = length(nd)

    latitude = Vector{Float64}(undef, N_nd)
    longitude = Vector{Float64}(undef, N_nd)
    node_map = Dict(n["id"] => attributes(n) for n in nodes)
    for i in 1:N_nd
        ref = nd[i]["ref"]
        haskey(node_map, ref) || throw(
            ArgumentError(
                "Segment file $path has nd ref $ref with no matching node"
            )
        )

        node_attrs = node_map[ref]
        haskey(node_attrs, "lat") || throw(
            ArgumentError(
                "Segment file $path node $ref has no lat"
            )
        )
        haskey(node_attrs, "lon") || throw(
            ArgumentError(
                "Segment file $path node $ref has no lon"
            )
        )

        latitude[i] = parse(Float64, node_attrs["lat"])
        longitude[i] = parse(Float64, node_attrs["lon"])
    end

    way_tags = Dict(t["k"] => t["v"] for t in filter(x -> tag(x) == "tag", way_children))
    haskey(way_tags, "name") || @warn "Segment file $path has no name"
    name = get(way_tags, "name", "")

    return Segment(name, latitude, longitude)
end
