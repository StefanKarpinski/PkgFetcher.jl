# simple standalone implementation of applying a bsdiff patch

module BSPatch

export bspatch

using Base: AbstractCmd

const MAGIC = codeunits("BSDIFF40")

int_io(x::Signed) = ifelse(x == abs(x), x, typemin(x) - x)
read_int(io::IO) = Int(int_io(read(io, Int64)))

function read_int(data::AbstractVector{UInt8}, i::Int)
    1 ≤ i ≤ i + 7 ≤ length(data) || error("corrupt bsdiff patch")
    p = convert(Ptr{Int64}, pointer(data, i))
    n = GC.@preserve data unsafe_load(p)
    return Int(int_io(n))
end

const bzcat = `bzcat`

function bspatch(
    old_data   :: Vector{UInt8},
    new_io     :: IO,
    patch_data :: Vector{UInt8},
)
    for i = 1:min(length(MAGIC), length(patch_data))
        MAGIC[i] == patch_data[i] || error("corrupt bsdiff patch")
    end
    index = length(MAGIC) + 1
    ctrl_size = read_int(patch_data, index); index += 8
    diff_size = read_int(patch_data, index); index += 8
    new_size  = read_int(patch_data, index); index += 8
    ctrl_r = index : (index + ctrl_size) - 1; index += ctrl_size
    diff_r = index : (index + diff_size) - 1; index += diff_size
    data_r = index : length(patch_data)
    @assert length(MAGIC)+3*8+1 == first(ctrl_r)
    @assert last(ctrl_r)+1 == first(diff_r)
    @assert last(diff_r)+1 == first(data_r)
    @assert last(data_r) == length(patch_data)
    ctrl_io = open(bzcat, read=true, write=true)
    diff_io = open(bzcat, read=true, write=true)
    data_io = open(bzcat, read=true, write=true)
    @sync begin
        @async (write(ctrl_io, @view patch_data[ctrl_r]); close(ctrl_io.in))
        @async (write(diff_io, @view patch_data[diff_r]); close(diff_io.in))
        @async (write(data_io, @view patch_data[data_r]); close(data_io.in))

        # apply the patch
        old_pos = new_pos = 0
        old_size = length(old_data)
        while !eof(ctrl_io)
            diff_size = read_int(ctrl_io)
            eof(ctrl_io) && error("corrupt bsdiff patch")
            copy_size = read_int(ctrl_io)
            eof(ctrl_io) && error("corrupt bsdiff patch")
            skip_size = read_int(ctrl_io)

            # sanity checks
            0 ≤ diff_size && 0 ≤ copy_size &&                # block sizes are non-negative
            new_pos + diff_size + copy_size ≤ new_size &&    # don't write > new_size bytes
            0 ≤ old_pos && old_pos + diff_size ≤ old_size || # bounds check for old data
                error("corrupt bsdiff patch")

            for i = 1:diff_size
                write(new_io, old_data[old_pos + i] + read(diff_io, UInt8))
            end
            for i = 1:copy_size
                write(new_io, read(data_io, UInt8))
            end

            new_pos += diff_size + copy_size
            old_pos += diff_size + skip_size
        end
        close(ctrl_io)
        close(diff_io)
        close(data_io)
    end
    flush(new_io)
end

function bspatch(
    old   :: Union{AbstractString, AbstractCmd},
    new   :: Union{AbstractString, AbstractCmd},
    patch :: Union{AbstractString, AbstractCmd},
)
    old_data = read(old)
    patch_data = read(patch)
    open(new, write=true) do new_io
        bspatch(old_data, new_io, patch_data)
    end
end

end # module
