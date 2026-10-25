import json
import struct
import os
import sys

def convert_gltf_to_obj(gltf_path, obj_path):
    print(f"[gltf_to_obj] Lendo modelo 3D: {gltf_path}")
    base_dir = os.path.dirname(os.path.abspath(gltf_path))
    
    buffers_data = []
    gltf = {}
    
    # Suporte a GLB (glTF binário autônomo)
    if gltf_path.lower().endswith(".glb"):
        with open(gltf_path, 'rb') as f:
            magic, version, length = struct.unpack('<4sII', f.read(12))
            if magic != b'glTF':
                raise ValueError("Arquivo inválido: assinatura GLB não encontrada.")
            while f.tell() < length:
                chunk_len, chunk_type = struct.unpack('<I4s', f.read(8))
                chunk_data = f.read(chunk_len)
                if chunk_type == b'JSON':
                    gltf = json.loads(chunk_data.decode('utf-8'))
                elif chunk_type == b'BIN\x00':
                    buffers_data.append(chunk_data)
    else:
        with open(gltf_path, 'r', encoding='utf-8') as f:
            gltf = json.load(f)
            
        for buf in gltf.get('buffers', []):
            buf_uri = buf.get('uri', '')
            if buf_uri.startswith('data:'):
                import base64
                data_b64 = buf_uri.split(',', 1)[1]
                buffers_data.append(base64.b64decode(data_b64))
            else:
                buf_path = os.path.join(base_dir, buf_uri)
                print(f"[gltf_to_obj] Carregando buffer binario: {buf_path} ({os.path.getsize(buf_path):,} bytes)")
                with open(buf_path, 'rb') as bf:
                    buffers_data.append(bf.read())
            
    buffer_views = gltf.get('bufferViews', [])
    accessors = gltf.get('accessors', [])
    
    def read_accessor(acc_idx):
        acc = accessors[acc_idx]
        bv_idx = acc.get('bufferView')
        if bv_idx is None:
            return []
        bv = buffer_views[bv_idx]
        buf = buffers_data[bv.get('buffer', 0)]
        
        start = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
        count = acc['count']
        comp_type = acc['componentType'] # 5123=ushort, 5125=uint, 5126=float
        acc_type = acc['type'] # SCALAR, VEC2, VEC3, VEC4
        stride = bv.get('byteStride', 0)
        
        comp_fmt = {5123: 'H', 5125: 'I', 5126: 'f'}[comp_type]
        comp_size = {5123: 2, 5125: 4, 5126: 4}[comp_type]
        num_comps = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[acc_type]
        
        elem_size = comp_size * num_comps
        actual_stride = stride if stride > 0 else elem_size
        
        items = []
        for i in range(count):
            offset = start + i * actual_stride
            chunk = buf[offset : offset + elem_size]
            val = struct.unpack('<' + comp_fmt * num_comps, chunk)
            if num_comps == 1:
                items.append(val[0])
            else:
                items.append(val)
        return items

    nodes = gltf.get('nodes', [])
    meshes = gltf.get('meshes', [])
    
    print(f"[gltf_to_obj] Processando {len(nodes)} nos e {len(meshes)} malhas...")
    
    total_v = 0
    total_vn = 0
    total_vt = 0
    total_f = 0
    
    with open(obj_path, 'w', encoding='utf-8') as out:
        out.write("# Arboria Engine OBJ Exporter - New Sponza Curtains\n")
        
        v_offset = 1
        vt_offset = 1
        vn_offset = 1
        
        for node_idx, node in enumerate(nodes):
            mesh_idx = node.get('mesh')
            if mesh_idx is None:
                continue
            mesh = meshes[mesh_idx]
            node_name = node.get('name', f"mesh_{mesh_idx}")
            out.write(f"\no {node_name}\n")
            
            # Simple transform
            trans = node.get('translation', [0.0, 0.0, 0.0])
            rot = node.get('rotation', [0.0, 0.0, 0.0, 1.0]) # qx, qy, qz, qw
            scale = node.get('scale', [1.0, 1.0, 1.0])
            
            # Quat to matrix
            qx, qy, qz, qw = rot
            r00 = 1 - 2 * (qy*qy + qz*qz)
            r01 = 2 * (qx*qy - qz*qw)
            r02 = 2 * (qx*qz + qy*qw)
            
            r10 = 2 * (qx*qy + qz*qw)
            r11 = 1 - 2 * (qx*qx + qz*qz)
            r12 = 2 * (qy*qz - qx*qw)
            
            r20 = 2 * (qx*qz - qy*qw)
            r21 = 2 * (qy*qz + qx*qw)
            r22 = 1 - 2 * (qx*qx + qy*qy)
            
            def transform_point(p):
                # scale
                sx, sy, sz = p[0] * scale[0], p[1] * scale[1], p[2] * scale[2]
                # rotate
                rx = r00 * sx + r01 * sy + r02 * sz
                ry = r10 * sx + r11 * sy + r12 * sz
                rz = r20 * sx + r21 * sy + r22 * sz
                # translate
                return (rx + trans[0], ry + trans[1], rz + trans[2])

            def transform_normal(n):
                # rotate
                rx = r00 * n[0] + r01 * n[1] + r02 * n[2]
                ry = r10 * n[0] + r11 * n[1] + r12 * n[2]
                rz = r20 * n[0] + r21 * n[1] + r22 * n[2]
                l = (rx*rx + ry*ry + rz*rz) ** 0.5
                if l > 0.000001:
                    return (rx/l, ry/l, rz/l)
                return (0.0, 1.0, 0.0)

            for prim in mesh.get('primitives', []):
                attrs = prim.get('attributes', {})
                pos_acc = attrs.get('POSITION')
                norm_acc = attrs.get('NORMAL')
                uv_acc = attrs.get('TEXCOORD_0')
                ind_acc = prim.get('indices')
                
                if pos_acc is None or ind_acc is None:
                    continue
                    
                positions = read_accessor(pos_acc)
                normals = read_accessor(norm_acc) if norm_acc is not None else []
                uvs = read_accessor(uv_acc) if uv_acc is not None else []
                indices = read_accessor(ind_acc)
                
                for p in positions:
                    tp = transform_point(p)
                    out.write(f"v {tp[0]:.6f} {tp[1]:.6f} {tp[2]:.6f}\n")
                total_v += len(positions)
                
                has_uv = len(uvs) > 0
                if has_uv:
                    for uv in uvs:
                        out.write(f"vt {uv[0]:.6f} {uv[1]:.6f}\n")
                    total_vt += len(uvs)
                    
                has_norm = len(normals) > 0
                if has_norm:
                    for n in normals:
                        tn = transform_normal(n)
                        out.write(f"vn {tn[0]:.6f} {tn[1]:.6f} {tn[2]:.6f}\n")
                    total_vn += len(normals)
                    
                for i in range(0, len(indices), 3):
                    i0 = indices[i]
                    i1 = indices[i+1]
                    i2 = indices[i+2]
                    
                    v0 = v_offset + i0
                    v1 = v_offset + i1
                    v2 = v_offset + i2
                    
                    if has_uv and has_norm:
                        vt0 = vt_offset + i0; vt1 = vt_offset + i1; vt2 = vt_offset + i2
                        vn0 = vn_offset + i0; vn1 = vn_offset + i1; vn2 = vn_offset + i2
                        out.write(f"f {v0}/{vt0}/{vn0} {v1}/{vt1}/{vn1} {v2}/{vt2}/{vn2}\n")
                    elif has_norm:
                        vn0 = vn_offset + i0; vn1 = vn_offset + i1; vn2 = vn_offset + i2
                        out.write(f"f {v0}//{vn0} {v1}//{vn1} {v2}//{vn2}\n")
                    elif has_uv:
                        vt0 = vt_offset + i0; vt1 = vt_offset + i1; vt2 = vt_offset + i2
                        out.write(f"f {v0}/{vt0} {v1}/{vt1} {v2}/{vt2}\n")
                    else:
                        out.write(f"f {v0} {v1} {v2}\n")
                    total_f += 1
                    
                v_offset += len(positions)
                if has_uv:
                    vt_offset += len(uvs)
                if has_norm:
                    vn_offset += len(normals)

    print(f"[gltf_to_obj] CONCLUIDO com sucesso: {obj_path}")
    print(f"  - Vertices: {total_v:,}")
    print(f"  - Normais: {total_vn:,}")
    print(f"  - UVs: {total_vt:,}")
    print(f"  - Triangulos/Faces: {total_f:,}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Uso: python gltf_to_obj.py <caminho_entrada.gltf|.glb> <caminho_saida.obj>")
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2]
    convert_gltf_to_obj(src, dst)
