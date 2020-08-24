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

function fetch(curl::Multi, resources::Resources)
    @sync for (resource, sources) in resources
        @async for source in sources
            while !fetch(curl, resource, source) end
        end
    end
end
fetch(resources::Resources) = fetch(Multi(), resources)

struct Tarball <: Source
    url::String
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

struct Patch <: Source
    url::String
    old::String
end

struct GitRepo <: Source
    url::String
    get::Bool
end

end # module
