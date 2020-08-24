module PkgFetcher

using Tar
using BSDiff
using Downloader
using Downloader.Curl: Multi

struct Resource
    hash::String
    dest::String
    # post::Function
    # TODO: add artifacts after package download
end

Resource(hash::AbstractString) = Resource(hash, tempname())

abstract type Source end

const Resources = Dict{Resource,<:AbstractVector{<:Source}}

struct Tarball <: Source
    url::String
end

struct Patch <: Source
    url::String
    old::String
end

struct GitRepo <: Source
    url::String
    get::Bool
end

fetch(resources::Resources) = fetch(Multi(), resources)

function fetch(curl::Multi, resources::Resources)
    @sync for (resource, sources) in resources
        @async for source in sources
            fetch(curl, resource, source) || continue
            if !isfile(resource.dest)
                @error "no download found" resource source
                continue
            end
            hash = Tar.tree_hash(`gzcat $(resource.dest)`)
            if hash != resource.hash
                @warn "hash mismatch" resource source hash
                rm(resource.dest, force=true)
                continue
            end
            break # success!
        end
    end
end

function fetch(curl::Multi, resource::Resource, source::Tarball)
    io = open(resource.dest, write=true)
    try
        # TODO: inject various Pkg headers
        request = Request(io, source.url, Pair{String,String}[])
        response = Downloader.get(request, curl) # TODO: hook up progress
        if response.status != 200
            @warn "tarball download failed" source.url response.status
            return false
        end
    catch error
        @warn "tarball download error" source.url error
        close(io)
        rm(resource.dest, force=true)
        return false
    end
    return true
end

function fetch(curl::Multi, resource::Resource, source::Patch)
    old_tar = tempname()
    skeleton = "$(source.old).skel"
    if isfile(skeleton)
        Tar.create(source.old, old_tar, skeleton=skeleton)
    else
        # no skeleton: assume everything is in the tarball
        Tar.create(source.old, old_tar)
    end

end

end # module
