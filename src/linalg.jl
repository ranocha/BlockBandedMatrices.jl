

function _scalemul!(α, A::AbstractMatrix, x::AbstractVector, β, y::AbstractVector,
                    ::AbstractBlockBandedInterface, xlayout, ylayout)
    if length(x) != size(A,2) || length(y) != size(A,1)
        throw(BoundsError())
    end

    scale!(β, y)
    o = one(eltype(y))

    for J = Block.(1:nblocks(A,2))
        for K = blockcolrange(A,J)
            kr,jr = globalrange(A, (K,J))
            scalemul!(α, view(A,K,J), view(x,jr), o, view(y,kr))
        end
    end
    y
end


function _scalemul!(α, A::AbstractMatrix, X::AbstractMatrix, β, Y::AbstractMatrix,
                    ::AbstractBlockBandedInterface, ::AbstractBlockBandedInterface, ::AbstractBlockBandedInterface)
    scale!(β, Y)
    o=one(eltype(Y))
    for J=Block(1):Block(nblocks(X,2)),
            N=blockcolrange(X,J), K=blockcolrange(A,N)
        scalemul!(o, view(A,K,N), view(X,N,J), o, view(Y,K,J))
    end
    Y
end

A_mul_B!(y::AbstractVector, A::AbstractBlockBandedMatrix, b::AbstractVector) =
    scalemul!(one(eltype(A)), A, b, zero(eltype(y)), fill!(y, zero(eltype(y))))

A_mul_B!(y::AbstractMatrix, A::AbstractBlockBandedMatrix, b::AbstractMatrix) =
    scalemul!(one(eltype(A)), A, b, zero(eltype(y)), fill!(y, zero(eltype(y))))



function *(A::BandedBlockBandedMatrix{T},
           B::BandedBlockBandedMatrix{V}) where {T<:Number,V<:Number}
    Arows, Acols = A.block_sizes.block_sizes.cumul_sizes
    Brows, Bcols = B.block_sizes.block_sizes.cumul_sizes
    if Acols ≠ Brows
        # diagonal matrices can be converted
        if isdiag(B) && size(A,2) == size(B,1) == size(B,2)
            # TODO: fix
            B = BandedBlockBandedMatrix(B.data, BlockSizes((Acols,Acols)), 0, 0, 0, 0)
        elseif isdiag(A) && size(A,2) == size(B,1) == size(A,1)
            A = BandedBlockBandedMatrix(A.data, BlockSizes((Brows,Brows)), 0, 0, 0, 0)
        else
            throw(DimensionMismatch("*"))
        end
    end
    n,m = size(A,1), size(B,2)

    bs = BandedBlockBandedSizes(BlockSizes((Arows,Bcols)), A.l+B.l, A.u+B.u, A.λ+B.λ, A.μ+B.μ)

    A_mul_B!(BandedBlockBandedMatrix{promote_type(T,V)}(uninitialized, bs),
             A, B)
end


######
# back substitution
######

@inline A_ldiv_B!(U::UpperTriangular{T, BlockBandedBlock{T}}, b::StridedVecOrMat{T}) where {T<:BlasFloat} =
    trtrs!('U', 'N', 'N', parent(U), b)


@inline hasmatchingblocks(A) =
    A.block_sizes.block_sizes.cumul_sizes[1] == A.block_sizes.block_sizes.cumul_sizes[2]

function A_ldiv_B!(U::UpperTriangular{T, BlockBandedMatrix{T}}, b::StridedVector) where T
    A = parent(U)

    @boundscheck size(A,1) == length(b) || throw(BoundsError(A))

    # When blocks are square, use LAPACK trtrs!
    if hasmatchingblocks(A)
        blockbanded_squareblocks_trtrs!(A, b)
    else
        blockbanded_rectblocks_trtrs!(A, b)
    end
end


function blockbanded_squareblocks_trtrs!(A::BlockBandedMatrix, b::StridedVector)
    @boundscheck size(A,1) == size(b,1) || throw(BoundsError())

    n = size(b,1)
    N = nblocks(A,1)

    for K = N:-1:1
        kr = globalrange(A.block_sizes, (K,K))[1]
        v = view(b, kr)
        for J = min(N,Int(blockrowstop(A,K))):-1:K+1
            jr = globalrange(A.block_sizes, (K,J))[2]
            gemv!('N', -one(eltype(A)), view(A,Block(K),Block(J)), view(b, jr), one(eltype(A)), v)
        end
        @inbounds A_ldiv_B!(UpperTriangular(view(A,Block(K),Block(K))), v)
    end

    b
end

# function blockbanded_rectblocks_trtrs!(R::BlockBandedMatrix{T},b::Vector) where T
#     n=n_end=length(b)
#     K_diag=N=Block(R.rowblocks[n])
#     J_diag=M=Block(R.colblocks[n])
#
#     while n > 0
#         B_diag = view(R,K_diag,J_diag)
#
#         kr = blockrows(R,K_diag)
#         jr = blockcols(R,J_diag)
#
#
#         k = n-kr[1]+1
#         j = n-jr[1]+1
#
#         skr = max(1,k-j+1):k   # range in the sub block
#         sjr = max(1,j-k+1):j   # range in the sub block
#
#         kr2 = kr[skr]  # diagonal rows/cols we are working with
#
#         for J = min(M,blockrowstop(R,K_diag)):-1:J_diag+1
#             B=view(R,K_diag,J)
#             Sjr = blockcols(R,J)
#
#             if J==M
#                 Sjr = Sjr[1]:n_end  # The sub rows of the rhs we will multiply
#                 gemv!('N',-one(T),view(B,skr,1:length(Sjr)),
#                                     view(b,Sjr),one(T),view(b,kr2))
#             else  # can use all columns
#                 gemv!('N',-one(T),view(B,skr,:),
#                                     view(b,Sjr),one(T),view(b,kr2))
#             end
#         end
#
#         if J_diag ≠ M && sjr[end] ≠ size(B_diag,2)
#             # subtract non-triangular columns
#             sjr2 = sjr[end]+1:size(B_diag,2)
#             gemv!('N',-one(T),view(B_diag,skr,sjr2),
#                             view(b,sjr2 + jr[1]-1),one(T),view(b,kr2))
#         elseif J_diag == M && sjr[end] ≠ size(B_diag,2)
#             # subtract non-triangular columns
#             Sjr = jr[1]+sjr[end]:n_end
#             gemv!('N',-one(T),view(B_diag,skr,sjr[end]+1:sjr[end]+length(Sjr)),
#                             view(b,Sjr),one(T),view(b,kr2))
#         end
#
#         trtrs!('U','N','N',view(B_diag,skr,sjr),view(b,kr2))
#
#         if k == j
#             K_diag -= 1
#             J_diag -= 1
#         elseif j < k
#             J_diag -= 1
#         else # if k < j
#             K_diag -= 1
#         end
#
#         n = kr2[1]-1
#     end
#     b
# end
#
#
# function trtrs!(A::BlockBandedMatrix{T},u::Matrix) where T
#     if size(A,1) < size(u,1)
#         throw(BoundsError())
#     end
#     n=size(u,1)
#     N=Block(A.rowblocks[n])
#
#     kr1=blockrows(A,N)
#     b=n-kr1[1]+1
#     kr1=kr1[1]:n
#
#     trtrs!('U','N','N',view(A,N[1:b],N[1:b]),view(u,kr1,:))
#
#     for K=N-1:-1:Block(1)
#         kr=blockrows(A,K)
#         for J=min(N,blockrowstop(A,K)):-1:K+1
#             if J==N  # need to take into account zeros
#                 gemm!('N',-one(T),view(A,K,N[1:b]),view(u,kr1,:),one(T),view(u,kr,:))
#             else
#                 gemm!('N',-one(T),view(A,K,J),view(u,blockcols(A,J),:),one(T),view(u,kr,:))
#             end
#         end
#         trtrs!('U','N','N',view(A,K,K),view(u,kr,:))
#     end
#
#     u
# end
