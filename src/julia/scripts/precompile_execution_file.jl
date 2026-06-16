const PRECOMPILE_BUNK_HOME = mktempdir(; cleanup=true)
const PRECOMPILE_ACTIVITY_STORE = joinpath(PRECOMPILE_BUNK_HOME, "activity_store")
mkpath(PRECOMPILE_ACTIVITY_STORE)

ENV["BUNK_HOME"] = PRECOMPILE_BUNK_HOME

Base.exit(::Integer) = nothing
Base.exit() = nothing

using Lunk

function fire_lunk(args::Vector{String})::Nothing
    original_args = copy(ARGS)
    try
        empty!(ARGS)
        append!(ARGS, args)
        try
            Lunk.main()
        catch
        end
    finally
        empty!(ARGS)
        append!(ARGS, original_args)
    end
    return nothing
end

fire_lunk(["segment", "list"])
fire_lunk(["--verbose", "segment", "list"])
fire_lunk(["--debug", "segment", "list"])
fire_lunk(["segment", "show", "missing-segment"])
fire_lunk(["segment", "remove", "missing-segment"])
fire_lunk(["segment", "match", "missing-segment"])
