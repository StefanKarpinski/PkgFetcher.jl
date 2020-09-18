module PkgFetcher

using Tar
using Downloads
using Downloads.Curl: Multi

using Gzip_jll: gzip_path
using zrl_jll: zrle_path, zrld_path

const gzip = `$gzip_path`
const gzcat = `$gzip_path -c -d`
const zrle = `$zrle_path`
const zrld = `$zrld_path`

include("BSPatch.jl")
using .BSPatch

function download(curl::Multi, url::String)
    path, io = mktemp()
    # TODO: add various Pkg headers
    request = Request(io, url, Pair{String,String}[])
    try
        response = Downloader.get(request, curl) # TODO: hook up progress
        response.status == 200 ||
            error("HTTP $(response.status) response")
    catch error
        @warn "download error" url error
        close(io)
        rm(path, force=true)
        return
    end
    close(io)
    return path
end

skeleton_file(path::AbstractString) = "$path.skel"

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
            tarball = fetch(curl, source)
            tarball === nothing && continue
            hash = Tar.tree_hash(`$zcat $tarball`)
            if hash != resource.hash
                @warn "hash mismatch" resource source hash
                rm(tarball, force=true)
                continue
            end
            skeleton = skeleton_file(resource.path)
            chmod(resource.path, 0o700, recursive=true)
            rm(resource.path, force=true, recursive=true)
            Tar.extract(`$zcat $tarball`, resource.path; skeleton)
            # mv(tarball, resource.path)
            break # success!
        end
    end
end

fetch(curl::Multi, source::Tarball) = download(curl, source.url)

function fetch(curl::Multi, source::Patch)
    patch = download(curl, source.url)
    patch === nothing && return
    try
        mktemp() do old_tarball, old_tar
            skeleton = skeleton_file(source.old)
            if isfile(skeleton)
                Tar.create(source.old, old_tar; skeleton)
            else
                # no skeleton: assume everything goes in the tarball
                # might fail or give wrong data, but we'll catch it
                Tar.create(source.old, old_tar)
            end
            close(old_tar)
            new_tarball = tempname()
            old_tar_zrl = `$zrle $old_tarball`
            new_tar_zrl = pipeline(zrld, gzip, new_tarball)
            try
                bspatch(old_tar_zrl, new_tar_zrl, patch)
            catch error
                @warn "could not apply patch" error
                rm(new_tarball, force=true)
                return
            end
            new_tarball
        end
    finally
        rm(patch, force=true)
    end
end

const SYSTEM_GIT = Ref{Union{Nothing,Bool}}(nothing)

function system_git()
    SYSTEM_GIT[] isa Bool && return SYSTEM_GIT[]
    SYSTEM_GIT[] = Sys.which("git") !== nothing
end

function fetch(curl::Multi, source::GitRepo)
    if system_git()
    else # use LibGit2 instead
    end
end

end # module
