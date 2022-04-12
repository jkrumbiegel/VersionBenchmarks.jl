module VersionBenchmarks

using Dates
using DataFrames
using Statistics: mean, std, median
import AlgebraOfGraphics
const AoG = AlgebraOfGraphics
import CairoMakie

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
    version::String
    julia::Cmd
end

Config(version) = Config(version, `julia`)

benchmark(configs, file::String; kwargs...) = benchmark(configs, [file]; kwargs...)

function benchmark(configs::Vector{Config}, files::AbstractVector{String};
        repetitions = 1,
        path = nothing,
        url = nothing,
    )

    if (path !== nothing && url !== nothing) || (path === nothing && url === nothing)
        throw(ArgumentError("path and url can't both be set or both be unset."))
    end
    if path !== nothing
        devdir = path
    else
        devdir = mktempdir()
        _run(`git clone $url $devdir`)
    end
    
    tmpdir = mktempdir()

    df = DataFrame()

    date = now()

    try
        @info "Copying repository to temp directory."
        pkgdir = joinpath(tmpdir, "package")
        cp(devdir, pkgdir)
        @info "Directory copied."

        # repetition should be the outer loop so that neither julia version nor code
        # version is blocked in time, which should give better robustness against
        # performance fluctuations of the system over time
        for repetition in 1:repetitions
            @info "Repetition $repetition of $repetitions."
            for config in configs
                julia_cmd = config.julia
                version = config.version
                julia_version = get_julia_version(julia_cmd)
                @info "Julia version $julia_version"
                @info "Checking out \"$version\"."

                checkout_version(pkgdir, version)
                
                commit_date = get_commit_date(pkgdir)
                commit = get_commit(pkgdir)

                # create a directory for the environment in which to install the version
                tmpenvdir = mktempdir()

                prepare_julia_environment(julia_cmd, tmpenvdir, pkgdir)

                for file in files
                    time_of_run = now()
                    resultdf = execute_file(file, julia_cmd, tmpenvdir, repetition)
                    duration_of_run = now() - time_of_run
                    resultdf.version .= version
                    resultdf.file .= file
                    resultdf.date .= date
                    resultdf.time_of_run .= time_of_run
                    resultdf.duration_of_run .= duration_of_run
                    resultdf.commit_date .= commit_date
                    resultdf.commit .= commit
                    resultdf.repetition .= repetition
                    resultdf.julia_version .= julia_version
                    append!(df, resultdf, cols = :union)
                end
            end
        end
    catch e
        rethrow(e)
    finally
        rm(tmpdir, recursive = true)
    end

    return df
end

checkout_version(pkgdir, version) = _run(`git -C $pkgdir checkout -f $version --`) # -f to throw away possible changes

get_commit(pkgdir) = strip(read(`git -C $pkgdir rev-parse --short HEAD`, String))
get_commit_date(pkgdir) = DateTime(
    strip(String(read(`git -C $pkgdir show -s --format=%ci`)))[1:end-6],
    "yyyy-mm-dd HH:MM:SS")
get_julia_version(julia_cmd) = read(`$julia_cmd --startup-file=no -e 'print(VERSION)'`, String)

function prepare_julia_environment(julia_cmd, tmpenvdir, pkgdir)
    code = """
    "@stdlib" ∉ LOAD_PATH && push!(LOAD_PATH, "@stdlib")
    using Pkg
    Pkg.UPDATED_REGISTRY_THIS_SESSION[] = true # avoid updating every time
    Pkg.activate("$tmpenvdir")
    Pkg.add(path = "$pkgdir"; io = devnull, preserve = Pkg.PRESERVE_ALL) # preserve possibly existing manifest
    Pkg.add("BenchmarkTools"; io = devnull, preserve = Pkg.PRESERVE_ALL)
    Pkg.precompile()
    """

    @info "Preparing Julia environment."
    _run(`$julia_cmd --startup-file=no -e $code`)
end

function execute_file(file, julia_cmd, tmpenvdir, repetition)
    @info "Executing file \"$file\"."

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
            println(io, (type = "time", name = \$name, time_s = dt, allocations = timed.bytes, gctime = timed.gctime))
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
                    type = "btime", 
                    name = \$name,
                    min_time_ns = minimum(bm.times),
                    median_time_ns = Statistics.median(bm.times),
                    mean_time_ns = Statistics.mean(bm.times),
                ))
                close(io)
            end
        end
    end
"""
end

function comparison(df, reference_version = nothing)
    df2 = select(df, ["version", "repetition", "name", "time", "allocations", "gctime"])
    df3 = combine(
        groupby(df2, ["version", "name"]),
        ["time", "allocations", "gctime"] .=> mean,
        renamecols = false
    )
    reference_version = something(reference_version, first(df3.version))

    function normalize(versions, values)
        i = findfirst(==(reference_version), versions)
        values ./ values[i]
    end

    sort(
        transform(
            groupby(df3, :name),
            vcat.(:version, [:time, :allocations, :gctime]) .=> normalize .=>
                [:time, :allocations, :gctime]
        ),
        :name
    )
end

function summarize_repetitions(df)
    gdf = groupby(df, [:version, :name, :julia_version])
    combine(gdf, :repetition => (x -> length(x)) => :n, [:time :allocations :gctime] .=> [mean, std, minimum, maximum])
end

function plot_summary(df, variable = :time)
    plt = AoG.data(df) *
        AoG.mapping(
            :version, variable;
            col = :name,
            row = :julia_version => x -> "Julia $x",
        ) *
        (AoG.expectation() + AoG.visual(strokewidth = 1, strokecolor = :black, color = :transparent))

    AoG.draw(plt,
        facet = (; linkyaxes = :none),
        axis = (;
            limits = (nothing, nothing, 0, nothing),
            xticklabelrotation = pi/6,
        ))
end

end
