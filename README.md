# VersionBenchmarks

A package to run benchmarks of different versions, branches, or commits of a repository against each other.

```julia
using VersionBenchmarks

df = VersionBenchmarks.benchmark(
    [
        # test master on default julia against an optimizations branch on julia nightly
        # (`julia_nightly` is a hypothetical command, use one that's correct on your system)
        Config("master", (path = path, rev = "master")),
        Config("optimizations", (path = path, rev = "optimizations-branch"), `julia_nightly`),
    ],
    testfile,
    repetitions = 10,
)
```

A `Config` takes a name, a `NamedTuple` or `Vector{NamedTuple}` that serve as input arguments for `Pkg.PackageSpec`s which should be installed, and optionally a command to run Julia which is `julia` by default.

Each test file is run once per repetition, with configs alternating so that the samples are spaced apart in time.

An example test file could look like this:

```julia
@vbtime "using TestRepo" begin
    using TestRepo
end

@vbbenchmark "Heavy computation" begin
    TestRepo.heavy_computation()
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
VersionBenchmarks.plot_summary(df [, :time]) # can change second arg to :allocations or :gctime
```

For example:

```julia
VersionBenchmarks.plot_summary(df)
```

![demo](demo.png)

