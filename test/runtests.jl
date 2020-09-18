using Test
using BSDiff
using PkgFetcher
using Pkg.Artifacts

@testset "BSPatch" begin
    registry_data = joinpath(artifact"test_data", "registry")
    old = joinpath(registry_data, "before.tar")
    new = joinpath(registry_data, "after.tar")
    patch = bsdiff(old, new)
    new′ = tempname()
    PkgFetcher.bspatch(old, new′, patch)
    @test read(new) == read(new′)
end

@testset "PkgFetcher.jl" begin
    # Write your tests here.
end
