module VersionBenchmarks

using Pkg
using Distributed
using Dates

function benchmark(pkgname::String, files::AbstractVector{String}, versions::AbstractVector{String}; repetitions = 1, directory = mktempdir())
    
    p = pwd()
    try
        @show directory
        cd(directory)
        ENV["JULIA_PKG_DEVDIR"] = directory

        Pkg.develop(pkgname)
        cd(pkgname)

        results = []

        for version in versions
            @info "checking out $version"
            run(`git checkout $version --`)
        
            # makieversion = match(r"version = \"(.*?)\"", read("Project.toml", String))[1]
            # glmakieversion = match(r"version = \"(.*?)\"", read("GLMakie/Project.toml", String))[1]
            # cairomakieversion = match(r"version = \"(.*?)\"", read("CairoMakie/Project.toml", String))[1]
            commit_date = DateTime(
                strip(String(read(`git show -s --format=%ci`)))[1:end-6],
                "yyyy-mm-dd HH:MM:SS")
        
            # df = DataFrame()
            date = now()
        
            for file in files
        
                local i_proc
                try
                    i_proc = addprocs(1)[1]
        
                    # @everywhere i_proc begin
                    #     using Pkg
                    # end
        
                    # @everywhere i_proc begin
                    #     pkg"activate --temp"
                    #     pkg"dev . MakieCore GLMakie CairoMakie"
                    #     Pkg.precompile()
                    #     @timed begin end
                    # end
        
                    # for part in parts
                    #     partname = match(r"^## (.*)", part)[1] |> strip
                    #     @info "executing part: $partname"
                    #     partcode = """
                    #         @timed begin
                    #             $part
                    #             nothing
                    #         end
                    #     """
                    #     timing = remotecall_fetch(i_proc, partcode) do p
                    #         include_string(Main, p)
                    #     end
        
                    #     push!(df, (
                    #         date = date,
                    #         commit_date = commit_date,
                    #         metric_target = metric_target,
                    #         juliaversion = string(Sys.VERSION),
                    #         makie = makieversion,
                    #         glmakie = glmakieversion,
                    #         cairomakie = cairomakieversion,
                    #         name = partname,
                    #         time = timing.time,
                    #         allocations = timing.bytes,
                    #         gc_time = timing.gctime,
                    #     ))
                    # end
        
                finally
                    rmprocs(i_proc)
                end    
            end
            # append!(results, df, cols = :union)
        end
    finally
        cd(p)
    end

    results
end

end
