#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <limits>
#include <array>
#include <stdexcept>
#include <vector>

#pragma pack(push, 1)
struct Header { char magic[8]; uint32_t version, vertices, indices, triangles, clusters, lods; float bmin[3], bmax[3]; uint32_t groups, base_triangles, reserved[2]; };
struct LOD { uint32_t level, offset, clusters, triangles; float error, ratio; };
struct Cluster { uint32_t id, lod; int32_t group, refined; float center[3], radius, cone[4], error; uint32_t vertex_offset, vertex_count, triangle_offset, triangle_count; };
struct Group { uint32_t id; int32_t depth; float center[3], radius, error; };
struct Vertex { float position[3], normal[3], uv[2]; };
#pragma pack(pop)
struct GPUCluster { float center_radius[4], cone[4], group_bounds[4], refined_bounds[4]; uint32_t offsets[4], info[4]; };
static_assert(sizeof(GPUCluster)==96);
static_assert(sizeof(Header)==72 && sizeof(LOD)==24 && sizeof(Cluster)==68 && sizeof(Group)==28 && sizeof(Vertex)==32);

template<class T> std::vector<T> read_array(std::ifstream& file, uint32_t count) {
    std::vector<T> result(count);
    if (count && !file.read(reinterpret_cast<char*>(result.data()), uint64_t(count)*sizeof(T))) throw std::runtime_error("truncated array");
    return result;
}
int main(int argc, char** argv) {
    try {
        if(argc!=2 && argc!=3) throw std::runtime_error("usage: vgmesh_reader <mesh.vgmesh> [gpu-clusters.bin]");
        std::ifstream file(argv[1], std::ios::binary | std::ios::ate);
        if(!file) throw std::runtime_error("cannot open mesh");
        auto size = uint64_t(file.tellg()); file.seekg(0);
        Header h{};
        if(!file.read(reinterpret_cast<char*>(&h),sizeof(h))) throw std::runtime_error("truncated header");
        if(std::memcmp(h.magic,"ARBORIA2",8)!=0 || h.version!=2) throw std::runtime_error("invalid ARBORIA2 header");
        uint64_t expected=sizeof(h)+uint64_t(h.lods)*sizeof(LOD)+uint64_t(h.clusters)*sizeof(Cluster)+uint64_t(h.groups)*sizeof(Group)+uint64_t(h.vertices)*sizeof(Vertex)+h.indices;
        if(expected!=size) throw std::runtime_error("binary size mismatch");
        auto lods=read_array<LOD>(file,h.lods);
        auto clusters=read_array<Cluster>(file,h.clusters);
        auto groups=read_array<Group>(file,h.groups);
        auto vertices=read_array<Vertex>(file,h.vertices);
        auto indices=read_array<uint8_t>(file,h.indices);
        for(const auto& lod:lods) if(uint64_t(lod.offset)+lod.clusters>h.clusters) throw std::runtime_error("LOD cluster range invalid");
        for(const auto& c:clusters) {
            if(c.lod>=h.lods || uint64_t(c.vertex_offset)+c.vertex_count>h.vertices || uint64_t(c.triangle_offset)+uint64_t(c.triangle_count)*3>h.indices) throw std::runtime_error("cluster range invalid");
            if(c.group < -1 || (c.group>=0 && uint32_t(c.group)>=h.groups)) throw std::runtime_error("cluster group invalid");
            if(c.refined < -1 || (c.refined>=0 && uint32_t(c.refined)>=h.groups)) throw std::runtime_error("cluster refined group invalid");
            for(uint64_t i=c.triangle_offset;i<uint64_t(c.triangle_offset)+c.triangle_count*3;i++) if(indices[i]>=c.vertex_count) throw std::runtime_error("local triangle index invalid");
        }
        if(argc==3) {
            std::vector<GPUCluster> gpu;
            gpu.reserve(clusters.size());
            for(const auto& c:clusters) {
                GPUCluster g{};
                for(int k=0;k<3;k++) { g.center_radius[k]=c.center[k]; g.cone[k]=c.cone[k]; }
                g.center_radius[3]=c.radius; g.cone[3]=c.cone[3];
                auto bounds=[&](int32_t id, float* out) {
                    if(id<0) { out[3]=-1.0f; return; }
                    if(uint32_t(id)>=groups.size()) throw std::runtime_error("refined group invalid");
                    const auto& b=groups[id];
                    for(int k=0;k<3;k++) out[k]=b.center[k];
                    out[3]=b.error;
                };
                bounds(c.group,g.group_bounds);
                bounds(c.refined,g.refined_bounds);
                g.offsets[0]=c.vertex_offset; g.offsets[1]=c.vertex_count;
                g.offsets[2]=c.triangle_offset; g.offsets[3]=c.triangle_count;
                g.info[0]=c.id; g.info[1]=c.lod;
                g.info[2]=uint32_t(c.group); g.info[3]=uint32_t(c.refined);
                gpu.push_back(g);
            }
            std::ofstream output(argv[2],std::ios::binary | std::ios::trunc);
            if(!output.write(reinterpret_cast<const char*>(gpu.data()),gpu.size()*sizeof(GPUCluster))) throw std::runtime_error("GPU cluster output failed");
            std::cout<<"GPU std430 cluster buffer: "<<gpu.size()*sizeof(GPUCluster)<<" bytes\n";
        }
        std::cout<<"ARBORIA2 validated: "<<h.vertices<<" vertices, "<<h.clusters<<" clusters, "<<h.lods<<" LODs, "<<h.groups<<" groups\n";
    } catch(const std::exception& e) { std::cerr<<"vgmesh error: "<<e.what()<<'\n'; return 1; }
}

