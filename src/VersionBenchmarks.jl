module VersionBenchmarks

using Dates
using DataFrames
using Statistics: mean, std, median
import AlgebraOfGraphics
const AoG = AlgebraOfGraphics
import CairoMakie

function __init__()
    CairoMakie.activate!(px_per_unit = 2)
end

run_without_std(cmd) = run(pipeline(cmd, stderr = devnull, stdout = devnull))

function benchmark(devdir, files::AbstractVector{String}, versions::AbstractVector{String};
        repetitions = 1,
        directory = mktempdir(),
        julia_exes = ["julia"],
    )
    
    p = pwd()
    tmpdir = mktempdir()

    df = DataFrame()

    date = now()

    try
        @info "Copying repository to temp directory."
        pkgdir = joinpath(tmpdir, "package")
        cp(devdir, pkgdir)
        @info "Directory copied."

        cd(pkgdir)

        # repetition should be the outer loop so that neither julia version nor code
        # version is blocked in time, which should give better robustness against
        # performance fluctuations of the system over time
        for repetition in 1:repetitions
            @info "Repetition $repetition of $repetitions."
            for julia_exe in julia_exes
                juliaversion = read(`$julia_exe -e 'print(VERSION)'`, String)
                @info "Julia version $juliaversion"
                for version in versions
                    @info "Checking out \"$version\"."
                    # -f to throw away possible changes
                    run_without_std(`git checkout -f $version --`)
                
                    commit_date = DateTime(
                        strip(String(read(`git show -s --format=%ci`)))[1:end-6],
                        "yyyy-mm-dd HH:MM:SS")
        
                    commit = strip(read(`git rev-parse --short HEAD`, String))

                    # create a directory for the environment in which to install the version
                    tmpenvdir = mktempdir()

                    code = """
                    using Pkg
                    Pkg.activate("$tmpenvdir")
                    Pkg.offline(true) # avoid package changes along the runs
                    Pkg.develop(path = "$pkgdir"; io = devnull)
                    Pkg.precompile()
                    """

                    @info "Preparing Julia environment."
                    run_without_std(`$julia_exe -e $code`)

                    for file in files

                        @info "Executing file \"$file\"."

                        resultpath, resultio = mktemp()

                        basecode = """
                            using Pkg
                            Pkg.activate("$tmpenvdir")

                            macro vbtime(name, expr)
                                @assert name isa String
                                quote
                                    io = open("$resultpath", "a")
                                    @timed 1 + 1
                                    tstart = time_ns()
                                    timed = @timed(\$(esc(expr)))
                                    dt = (time_ns() - tstart) / 1_000_000_000
                                    println(io, (name = \$name, time = dt, timedtime = timed.time, allocations = timed.bytes, gctime = timed.gctime))
                                    close(io)
                                end
                            end
                        """

                        testcode = read(file, String)

                        fullcode = join([basecode, testcode], "\n")

                        path, io = mktemp()
                        open(path, "w") do file
                            println(file, fullcode)
                        end

                        # execute the modified code, this should write results to the temp file at `resultpath`
                        run_without_std(`$julia_exe $path`)

                        for line in readlines(resultpath)
                            # the file should only have lines with serialized NamedTuples
                            lineresult = Dict(pairs(eval(Meta.parse(line))))
                            lineresult[:version] = version
                            lineresult[:file] = file
                            lineresult[:date] = date
                            lineresult[:commit_date] = commit_date
                            lineresult[:commit] = commit
                            lineresult[:repetition] = repetition
                            lineresult[:juliaversion] = juliaversion
                            push!(df, lineresult, cols = :union)
                        end
                    end
                end
            end
        end
    catch e
        rethrow(e)
    finally
        rm(tmpdir, recursive = true)
        cd(p)
    end

    return df
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
    gdf = groupby(df, [:version, :name, :juliaversion])
    combine(gdf, :repetition => (x -> length(x)) => :n, [:time :allocations :gctime] .=> [mean, std, minimum, maximum])
end

function plot_summary(df, variable = :time)
    plt = AoG.data(df) *
        AoG.mapping(
            :version, variable;
            col = :name,
            row = :juliaversion => x -> "Julia $x",
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
