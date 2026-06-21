using SQLite
using Dates
using Lunk

const matcher_version = 20260620

"""
    load_activities(activities::Vector{Tuple{Int, String}})::Dict{Int, CacheData}

Load cached `CacheData` objects for a vector of `(activity_id, source_fingerprint)`
tuples and return a `Dict` keyed by activity ID.
"""
function load_activities(
        activities::Vector{Tuple{Int, String}}
    )::Dict{Int, CacheData}
    return Dict(
        id => fingerprint |> resolve_cache_path |> read_cache
            for (id, fingerprint) in activities
    )
end

struct MatchResult
    activity_date::DateTime
    activity_id::Int64
    segment_time::Float64
    matched_at::Int64
end

"""
    match_to_activities(segment::Segment, activities::Dict{Int, CacheData})::Vector{MatchResult}

Match a single `Segment` to a `Dict` of decode artifacts keyed by activity ID.

Calculations are performed in cartesian ECEF coordinates using the WGS84
ellipsoid, with both the `segment` and `activities` GPS tracks shifted to the
ellipsoid's surface (i.e. the height coordinate of the `activities` is
ignored. For each individual activity, NaN valued GPS tracks (in either of
lat/lon) are dropped from the activity prior to matching, such that the non-NaN
points adjacent to the NaN(s) are treated as an edge. This mostly of consequence
for the gate crossing detection and interpolation, since it influences the gate
crossing angle, hence influencing the crossing time and crossing affirmation.

The start/finish gates used in the matching algorithm are defined by the vectors
connecting the first/last `segment` points to their neighbors. The gates are
thus directional, and crossings are only valid when they are in the same
direction as the gate vectors.

The gate crossing times for each match are calculated by linearly interpolating
the timestamps of the crossing edge's track points. In other words, the
algorithm assumes that the user is traveling at a constant velocity along the
crossing edge.

A match is considered valid only when all sampled track points between the
start/finish gate crossings are within the segment polyline cooridoor defined by
`tape_radius`. Gate crossings must also occur within `tape_radius` of the
first/last segment points in order to be registered.
"""
function match_to_activities(
        segment::Segment,
        activities::Dict{Int, CacheData}
    )::Vector{MatchResult}
    tape_radius = 15.0  # cooridor of allowed deviation off segment
    fixed_height = 0.0  # height above ellipsoid [m]

    activity_dates = Vector{DateTime}()
    activity_ids = Vector{Int64}()
    segment_times = Vector{Float64}()
    matched_at = Vector{Float64}()

    segment_ecef = compute_ecef_r.(segment.latitude, segment.longitude, fixed_height)
    # TODO: This conversion happens at each compute_ecef_r callsite. Consider
    # changing the return type
    seg = vcat(
        [s[1] for s in segment_ecef]',
        [s[2] for s in segment_ecef]',
        [s[3] for s in segment_ecef]'
    )

    # Start gate geometry
    s_0 = seg[:, 1]
    l_0 = seg[:, 2] - s_0  # Gate-normal vector

    # Finish gate geometry
    s_end = seg[:, end]
    l_end = s_end - seg[:, end - 1]  # Gate-normal vector

    for (activity_id, cache) in activities
        @debug "Working on activity $activity_id"
        @debug "Loaded $(length(cache.latitude)) track points"

        idx_start_crossings = Vector{Int64}()
        idx_end_crossings = Vector{Int64}()
        start_times = Vector{Float64}()
        end_times = Vector{Float64}()

        # Tracks can start with NaN, likely because the device hadn't acquired GPS
        # lock when the activity was started. Remove them
        filtered_cache = drop_invalid_gps_points(cache)

        track_ecef = compute_ecef_r.(
            filtered_cache.latitude, filtered_cache.longitude, fixed_height
        )
        num_track = length(track_ecef)
        if num_track == 0
            @debug "ECEF track conversion has zero points, skipping."
            continue
        end

        track = vcat(
            [t[1] for t in track_ecef]',
            [t[2] for t in track_ecef]',
            [t[3] for t in track_ecef]'
        )

        on_segment = false
        match_found = false
        for i in 1:(num_track - 1)
            p_1 = track[:, i]
            p_2 = track[:, i + 1]

            let start_crossing = crosses_gate(s_0, l_0, p_1, p_2, tape_radius)
                if start_crossing !== nothing
                    @debug "Found a start crossing at i = $i"
                    on_segment = true
                    t_cross = linterp(
                        filtered_cache.time[i],
                        filtered_cache.time[i + 1],
                        start_crossing.t
                    )
                    push!(idx_start_crossings, i)
                    push!(start_times, t_cross)
                end
            end

            if on_segment
                # Only 2 allowed outcomes when user is on segment:
                #  - User stays within bounds
                #  - User crosses the finish line
                if !on_polyline(p_1, seg, tape_radius)
                    @debug "User went off segment at i = $i"
                    on_segment = false
                    match_found = false
                    continue
                end

                let end_crossing = crosses_gate(s_end, l_end, p_1, p_2, tape_radius)
                    if end_crossing !== nothing
                        @debug "Found a finish crossing at i = $i"
                        t_cross = linterp(
                            filtered_cache.time[i],
                            filtered_cache.time[i + 1],
                            end_crossing.t
                        )
                        push!(idx_end_crossings, i)
                        push!(end_times, t_cross)
                        match_found = true
                        on_segment = false
                    end
                end
            end
        end

        if !match_found
            continue
        end

        segment_time = end_times[1] - start_times[1]

        push!(activity_dates, unix2datetime(cache.start_time))
        push!(activity_ids, activity_id)
        push!(segment_times, segment_time)
        push!(matched_at, round(Int, time()))

    end
    return MatchResult.(activity_dates, activity_ids, segment_times, matched_at)
end
