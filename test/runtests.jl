using VersionBenchmarks
using Test

VersionBenchmarks.hide_output[] = false

versions = [
    Config("master", [(name="Colors", rev="master")]),
    Config("0.12.7", [(name="Colors", version="0.12.7")]),
    Config("0.12.0", [(name="Colors", version="0.12.0")]),
    Config("0.10.2", [(name="Colors", version="0.10.2")]),
]

dataframe = benchmark(
    versions,
    joinpath(@__DIR__, "test.jl"),
    repetitions = 5,
)

@testset "most basic tests" begin
    @test length(dataframe.time_s) == 40
    @test length(names(dataframe)) == 13
    @test all(x-> x > 0.01, dataframe.time_s)

    figure_grid = VersionBenchmarks.plot_summary(dataframe)
    @test figure_grid isa VersionBenchmarks.AoG.FigureGrid
end
