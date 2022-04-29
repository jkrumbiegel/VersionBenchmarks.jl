resultpath, _repetition = ARGS
repetition = parse(Int, _repetition)
import BenchmarkTools
import Statistics

macro vbtime(name, expr)
    @assert name isa String
    quote
        io = open(resultpath, "a")
        gc_stats = Base.gc_num()
        tstart = time_ns()
        timed = $(esc(expr))
        dt = (time_ns() - tstart) / 1e9
        gc_diff = Base.GC_Diff(Base.gc_num(), gc_stats)
        println(io, (
            type = "vbtime", name = $name, time_s = dt,
            alloc_bytes = gc_diff.allocd,
            gctime_s = gc_diff.total_time /  1e9))
        close(io)
    end
end

macro vbbenchmark(name, exprs...)
    @assert name isa String
    quote
        # only run vbbenchmark on first repetition
        if $repetition == 1
            io = open("$resultpath", "a")
            bm = BenchmarkTools.@benchmark $(exprs...)
            println(io, (
                type = "vbbenchmark",
                name = $name,
                min_time_ns = minimum(bm.times),
                max_time_ns = maximum(bm.times),
                median_time_ns = Statistics.median(bm.times),
                mean_time_ns = Statistics.mean(bm.times),
            ))
            close(io)
        end
    end
end
