# VersionBenchmarks

A package to run benchmarks of different versions, branches, or commits of a repository against each other.

Here's an example with the repository `TestRepo` included in the test folder of VersionBenchmarks:

```julia
using VersionBenchmarks

testpath(args...) = normpath(joinpath(pathof(VersionBenchmarks), "..", "..", "test", args...))

df = VersionBenchmarks.benchmark(
    testpath("TestRepo"),
    [testpath("test.jl")],
    ["optimizations", "master"], # vector of tags, branches or commits
    repetitions = 10,
    julia_exes = ["julia"] # optionally specify different julia commands for different versions
)
```

Each test file is run once per repetition, with code versions and julia versions alternating so that the samples for one code version and julia version are spaced apart in time.

The example test file looks like this:

```julia
@vbtime "using TestRepo" begin
    using TestRepo
end

@vbtime "Heavy computation" begin
    TestRepo.heavy_computation()
end
```

The `@vbtime` macros save timing, allocation and gctime info in a file.
The results are then passed back in a `DataFrame`.

You can call these functions on it:

```julia
VersionBenchmarks.summarize_repetitions(df)
VersionBenchmarks.plot_summary(df [, :time]) # can change second arg to :allocations or :gctime
```

For example:

```julia
VersionBenchmarks.plot_summary(df)
```

![demo](demo.png)

