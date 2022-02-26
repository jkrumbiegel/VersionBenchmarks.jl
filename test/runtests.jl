using VersionBenchmarks
using Test

@testset "VersionBenchmarks.jl" begin
    df = VersionBenchmarks.benchmark(
        joinpath(@__DIR__, "TestRepo"),
        [joinpath(@__DIR__, "test.jl")],
        ["master", "optimizations"],
        repetitions = 10
    )
end
