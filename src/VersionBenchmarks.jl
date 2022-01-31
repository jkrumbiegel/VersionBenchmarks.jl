module VersionBenchmarks

using Dates
using DataFrames
using Statistics: mean

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
        @info "copying repository to temp directory"
        pkgdir = joinpath(tmpdir, "package")
        cp(devdir, pkgdir)
        @info "directory copied"

        cd(pkgdir)

        for version in versions
            @info "checking out $version"
            # -f to throw away possible changes
            run(`git checkout -f $version --`)
        
            commit_date = DateTime(
                strip(String(read(`git show -s --format=%ci`)))[1:end-6],
                "yyyy-mm-dd HH:MM:SS")

            commit = strip(read(`git rev-parse --short HEAD`, String))
                
            for file in files, julia_exe in julia_exes, repetition in 1:repetitions

                resultpath, resultio = mktemp()

                basecode = """
                using Pkg
                pkg"activate --temp"
                Pkg.add(path = "$pkgdir")
                Pkg.precompile()

                macro _timed(name, expr)
                    quote
                        io = open("$resultpath", "a")
                        timed = @timed(\$(esc(expr)))
                        println(io, (name = \$name, time = timed.time, allocations = timed.bytes, gctime = timed.gctime))
                        close(io)
                    end
                end
                """

                testcode = read(file, String)
                modified_testcode = replace(
                    testcode,
                    r"#\s+(\w[\w ]*\w)\s+@timed" => s"@_timed \"\1\""
                )

                fullcode = join([basecode, modified_testcode], "\n")

                path, io = mktemp()
                open(path, "w") do file
                    println(file, fullcode)
                end

                juliaversion = read(`$julia_exe -e 'print(VERSION)'`, String)

                # execute the modified code, this should write results to the temp file at `resultpath`
                run(`$julia_exe $path`)

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

end
