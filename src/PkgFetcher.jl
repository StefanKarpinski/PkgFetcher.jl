module PkgFetcher

using Tar
using BSDiff
using Downloader
using Downloader.Curl: Multi

struct Resource
    hash::String
    path::String
    # TODO: add artifacts after package download
    # post::Function
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
            if !isfile(resource.path)
                @error "no download found" resource source
                continue
            end
            hash = Tar.tree_hash(`gzcat $(resource.path)`)
            if hash != resource.hash
                @warn "hash mismatch" resource source hash
                rm(resource.path, force=true)
                continue
            end
            break # success!
        end
    end
end

function fetch(curl::Multi, resource::Resource, source::Tarball)
    download(curl, source.url, resource.path)
end

function fetch(curl::Multi, resource::Resource, source::Patch)
    old_tar = tempname()
    skeleton = "$(source.old).skel"
    if isfile(skeleton)
        Tar.create(source.old, old_tar, skeleton=skeleton)
    else
        # no skeleton: assume everything goes in the tarball
        # might fail or give wrong data, but we'll catch it
        Tar.create(source.old, old_tar)
    end
    patch = tempname()
    download(curl, source.url, patch) || return false
    output = pipeline(`gzip`, resource.path)
    try bspatch(old_tar, output, patch)
    catch error
        @warn "could not apply patch" error
        return false
    end
    return true
end

function download(curl::Multi, url::String, path::AbstractString)
    io = open(path, write=true)
    try
        # TODO: inject various Pkg headers
        request = Request(io, url, Pair{String,String}[])
        response = Downloader.get(request, curl) # TODO: hook up progress
        if response.status != 200
            @warn "download failed" url response.status
            return false
        end
    catch error
        @warn "download error" url error
        close(io)
        rm(path, force=true)
        return false
    end
    return true
end

end # module
