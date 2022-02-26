@vbtime "using TestRepo" begin
    using TestRepo
end

@vbtime "Heavy computation" begin
    TestRepo.heavy_computation()
end
