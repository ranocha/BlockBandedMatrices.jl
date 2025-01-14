using Documenter, BlockBandedMatrices

makedocs(
    modules = [BlockBandedMatrices],
    sitename = "BlockBandedMatrices.jl",
    strict = false, # VERSION.major == 1 && sizeof(Int) == 8, # only strict mode on 1.0 and Int64
    pages = Any[
        "Home" => "index.md"
    ]
)


deploydocs(
    repo   = "github.com/JuliaLinearAlgebra/BlockBandedMatrices.jl.git",
    )
