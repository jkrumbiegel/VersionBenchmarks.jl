# VersionBenchmarks

A package to run benchmarks of different versions, branches, or commits of a repository against each other.

Basic usage:

```julia
using VersionBenchmarks

df = VersionBenchmarks.benchmark(
    path_to_package,
    vector_of_test_file_paths,
    ["optimizations", "master"], # vector of tags, branches or commits
    repetitions = 10,
    julia_exes = ["julia"] # optionally specify different julia commands for different versions
)
```

Each test file is run once per repetition, with code versions and julia versions alternating so that the samples for one code version and julia version are spaced apart in time.

A code file can look like this:

```julia
@vbtime "using the package" begin
    using MyPackage
end

@vbtime "a heavy computation" begin
    MyPackage.heavy_computation()
end
```

The `@vbtime` macros save timing, allocation and gctime info in a file.
The results are then passed back in a `DataFrame`.

You can call these functions on it:

```julia
VersionBenchmarks.summarize_repetitions(df)
VersionBenchmarks.plot_summary(df [, :time]) # can change second arg to :allocations or :gctime

