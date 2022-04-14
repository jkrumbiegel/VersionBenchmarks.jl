module VersionBenchmarks

using Dates
using DataFrames
using Statistics: mean, std, median
import AlgebraOfGraphics
const AoG = AlgebraOfGraphics
import CairoMakie
import Pkg

export Config
export benchmark

const hide_output = Ref(true)

function __init__()
    CairoMakie.activate!(px_per_unit = 2)
end

function _run(cmd)
    if hide_output[]
        run(pipeline(cmd, stderr = devnull, stdout = devnull))
    else
        run(cmd)
    end
end

struct Config
    name::String
    pkgspecs::Vector{NamedTuple}
    julia::Cmd
end

Config(name, pkgspec::NamedTuple, julia) = Config(name, [pkgspec], julia)
Config(name, pkgspecs) = Config(name, pkgspecs, `julia`)

benchmark(configs, file::String; kwargs...) = benchmark(configs, [file]; kwargs...)

function benchmark(configs::Vector{Config}, files::AbstractVector{String};
        repetitions = 1
    )

    tmpdir = mktempdir()

    df = DataFrame()

    date = now()

    tmpdir_dict = Dict()

    try
        # repetition should be the outer loop so that neither julia version nor code
        # version is blocked in time, which should give better robustness against
        # performance fluctuations of the system over time
        n_runs = repetitions * length(configs)
        start = time()
        i = 0
        for repetition in 1:repetitions
            for (iconfig, config) in enumerate(configs)
                i += 1
                julia_cmd = config.julia
                julia_version = get_julia_version(julia_cmd)

                println("""
                    Repetition $repetition of $repetitions, config $iconfig of $(length(configs)).
                     ├ Name: $(config.name)
                     └ Julia: $julia_version""")

                tmpenvdir = prepare_julia_environment(config, tmpdir_dict)

                for file in files
                    time_of_run = now()
                    
                    print("   Executing \"$file\"...")
                    t = time()
                    resultdf = execute_file(file, julia_cmd, tmpenvdir, repetition)
                    println(" Done. ($(round(Int, time() - t))s)")

                    duration_of_run = now() - time_of_run
                    resultdf.config_name .= config.name
                    resultdf.pkgspecs .= Ref(config.pkgspecs)
                    resultdf.file .= file
                    resultdf.date .= date
                    resultdf.time_of_run .= time_of_run
                    resultdf.duration_of_run .= duration_of_run
                    resultdf.repetition .= repetition
                    resultdf.julia_version .= julia_version
                    append!(df, resultdf, cols = :union)
                end

                elapsed = time() - start
                estimated = elapsed / i * (n_runs - i)
                println("   Time elapsed: $(round(Int, elapsed))s.")
                println("   Estimated remaining: $(round(Int, estimated))s.")
                println("   Estimated finish time: $(Dates.format(now() + Second(round(Int, estimated)), "HH:MM")).")
            end
        end
    catch e
        rethrow(e)
    finally
        rm(tmpdir, recursive = true)
    end

    return df
end

get_julia_version(julia_cmd) = read(`$julia_cmd --startup-file=no -e 'print(VERSION)'`, String)

function prepare_julia_environment(config, tmpdir_dict)
    if haskey(tmpdir_dict, config)
        tmpenvdir = tmpdir_dict[config]

        code = """
        "@stdlib" ∉ LOAD_PATH && push!(LOAD_PATH, "@stdlib")
        using Pkg
        Pkg.UPDATED_REGISTRY_THIS_SESSION[] = true # avoid updating every time
        Pkg.activate("$tmpenvdir")
        Pkg.precompile()
        """
    else
        # create a directory for the environment in which to install the version
        tmpenvdir = mktempdir()
        tmpdir_dict[config] = tmpenvdir

        specs = [config.pkgspecs; (;name = "BenchmarkTools")]
        specstring = string(specs) # TODO: other way to transfer package specs to the new process?

        code = """
        "@stdlib" ∉ LOAD_PATH && push!(LOAD_PATH, "@stdlib")
        using Pkg
        Pkg.UPDATED_REGISTRY_THIS_SESSION[] = true # avoid updating every time
        Pkg.activate("$tmpenvdir")
        Pkg.add($specstring; $(hide_output[] ? "io = devnull, " : ""))
        Pkg.precompile()
        """
    end
    print("   Preparing Julia environment...")
    t = time()
    _run(`$(config.julia) --startup-file=no -e $code`)
    println(" Done. ($(round(Int, time() - t))s)")
    return tmpenvdir
end

function execute_file(file, julia_cmd, tmpenvdir, repetition)
    resultpath, resultio = mktemp()

    basecode = get_basecode(tmpenvdir, resultpath, repetition)

    testcode = read(file, String)

    fullcode = join([basecode, testcode], "\n")

    path, io = mktemp()
    open(path, "w") do file
        println(file, fullcode)
    end

    # execute the modified code, this should write results to the temp file at `resultpath`
    _run(`$julia_cmd --startup-file=no $path`)

    results = foldl(((a, b) -> push!(a, b, cols = :union)),
        map(parse_result_line, readlines(resultpath)),
        init = DataFrame())
    return results
end

function parse_result_line(line)
    # the file should only have lines with serialized NamedTuples
    lineresult = Dict(pairs(eval(Meta.parse(line))))
end

function get_basecode(tmpenvdir, resultpath, repetition)
    """
    "@stdlib" ∉ LOAD_PATH && push!(LOAD_PATH, "@stdlib")
    using Pkg
    Pkg.activate("$tmpenvdir")
    import BenchmarkTools
    import Statistics

    macro vbtime(name, expr)
        @assert name isa String
        quote
            io = open("$resultpath", "a")
            @timed 1 + 1
            tstart = time_ns()
            timed = @timed(\$(esc(expr)))
            dt = (time_ns() - tstart) / 1_000_000_000
            println(io, (type = "vbtime", name = \$name, time_s = dt, alloc_bytes = timed.bytes, gctime_s = timed.gctime))
            close(io)
        end
    end

    macro vbbenchmark(name, exprs...)
        @assert name isa String
        quote
            # only run vbbenchmark on first repetition
            if $repetition == 1
                io = open("$resultpath", "a")
                bm = BenchmarkTools.@benchmark \$(exprs...)
                println(io, (
                    type = "vbbenchmark", 
                    name = \$name,
                    min_time_ns = minimum(bm.times),
                    max_time_ns = maximum(bm.times),
                    median_time_ns = Statistics.median(bm.times),
                    mean_time_ns = Statistics.mean(bm.times),
                ))
                close(io)
            end
        end
    end
"""
end

function summarize_repetitions(df)
    gdf = groupby(df, [:config_name, :name, :julia_version])
    combine(gdf, :repetition => (x -> length(x)) => :n, [:time_s :alloc_bytes :gctime_s] .=> [mean, std, minimum, maximum])
end

function plot_summary(df, variable = :time_s)
    df = dropmissing(df, variable)
    plt = AoG.data(df) *
        AoG.mapping(
            :config_name, variable;
            row = :name,
            col = :julia_version => x -> "Julia $x",
        ) *
        (AoG.expectation() + AoG.visual(strokewidth = 1, strokecolor = :black, color = :transparent))

    AoG.draw(plt,
        facet = (; linkyaxes = :minimal),
        axis = (;
            limits = (nothing, nothing, 0, nothing),
            xticklabelrotation = pi/6,
        ),
    )
end

end
