# VersionBenchmarks

A package to run benchmarks of different versions, branches, or commits of a repository against each other.

```julia
using VersionBenchmarks

df = benchmark(
    [
        Config("master", (name = "DataFrames", rev = "master")),
        Config("1.0", (name = "DataFrames", version = "v1.0.0")),
        Config("master", (name = "DataFrames", rev = "master"),
            `/Applications/Julia-1.9.app/Contents/Resources/julia/bin/julia`),
        Config("1.0", (name = "DataFrames", version = "v1.0.0"),
            `/Applications/Julia-1.9.app/Contents/Resources/julia/bin/julia`),
    ],
    "dataframes.jl",
    repetitions = 10,
)
```

A `Config` takes a name, a `NamedTuple` or `Vector{NamedTuple}` that serve as input arguments for `Pkg.PackageSpec`s which should be installed, and optionally a command to run Julia which is `julia` by default.

Each test file is run once per repetition, with configs alternating so that the samples are spaced apart in time.

An example file, `dataframes.jl`, looks like this:

```julia
@vbtime "using" begin
    using DataFrames
end

@vbtime "first_df" begin
    DataFrame(a = 1:10)
end

@vbbenchmark "DataFrame" begin
    DataFrame()
end
```

The `@vbtime` macros save timing, allocation and gctime info in a file.
They are run in every repetition.
The results are then passed back in a `DataFrame`.

You can also use `@vbbenchmark`, which is a wrapper for `BenchmarkTools.@benchmark`.
It only runs on the first repetition, because it includes its own repetitions already.
It saves minimumm, maximum, median and mean run time.

You can call these functions on the resulting DataFrame:

```julia
VersionBenchmarks.summarize_repetitions(df)
VersionBenchmarks.plot_summary(df [, :time_s]) # can change second arg to :allocations or :gctime
```

For example:

```julia
VersionBenchmarks.plot_summary(df)
```

![demo](demo.png)


```julia
VersionBenchmarks.plot_summary(df, :allocations)
```

![demo](demo_allocations.png)

