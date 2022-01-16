module VersionBenchmarks

using Dates
using DataFrames

function benchmark(devdir, files::AbstractVector{String}, versions::AbstractVector{String}; repetitions = 1, directory = mktempdir())
    
    p = pwd()
    tmpdir = mktempdir()

    df = DataFrame()

    try
        @info "copying directory"
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
        
            date = now()
        
            for file in files, repetition in 1:repetitions

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

                code = replace(
                    read(file, String),
                    r"#\s+(\w[\w ]*\w)\s+@timed" => s"@_timed \"\1\""
                )

                @show code
                fullcode = join([basecode, code], "\n")

                path, io = mktemp()
                open(path, "w") do file
                    println(file, fullcode)
                end
                run(`julia $path`)

                for line in readlines(resultpath)
                    lineresult = Dict(pairs(eval(Meta.parse(line))))
                    lineresult[:version] = version
                    lineresult[:file] = file
                    lineresult[:date] = date
                    lineresult[:commit_date] = commit_date
                    lineresult[:commit] = commit
                    lineresult[:repetition] = repetition
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


end
