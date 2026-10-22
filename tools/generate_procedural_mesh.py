import sys
import os
import math

def generate_procedural_terrain(output_path, grid_size=708, world_size=100.0):
    """
    Gera uma malha procedural OBJ com ~1.000.000 de triangulos (grid_size x grid_size x 2).
    708 x 708 x 2 = 1.002.528 triangulos.
    """
    print(f"Gerando malha procedural de ~1M triangulos ({grid_size}x{grid_size} quads)...")
    num_verts_x = grid_size + 1
    num_verts_y = grid_size + 1
    total_triangles = grid_size * grid_size * 2
    total_vertices = num_verts_x * num_verts_y
    print(f"Total vertices: {total_vertices:,} | Total triangulos: {total_triangles:,}")

    step = world_size / float(grid_size)
    half_size = world_size * 0.5

    with open(output_path, "w", buffering=1024*1024) as f:
        f.write(f"# ARBORIA ENGINE - Procedural Mesh Benchmark (~1M Triangles)\n")
        f.write(f"# Vertices: {total_vertices}, Triangles: {total_triangles}\n")

        # Vertices (v)
        for iy in range(num_verts_y):
            y_norm = iy / float(grid_size)
            pz = -half_size + iy * step
            for ix in range(num_verts_x):
                x_norm = ix / float(grid_size)
                px = -half_size + ix * step
                # Altura procedural suave com multiplas frequencias
                py = (math.sin(x_norm * math.pi * 6.0) * math.cos(y_norm * math.pi * 6.0) * 4.0 +
                      math.sin(x_norm * math.pi * 14.0) * 1.5 +
                      math.cos(y_norm * math.pi * 18.0) * 1.2)
                f.write(f"v {px:.5f} {py:.5f} {pz:.5f}\n")

        # Coordenadas UV (vt)
        for iy in range(num_verts_y):
            v = iy / float(grid_size)
            for ix in range(num_verts_x):
                u = ix / float(grid_size)
                f.write(f"vt {u:.5f} {v:.5f}\n")

        # Normais (vn) aproximadas analiticamente
        for iy in range(num_verts_y):
            y_norm = iy / float(grid_size)
            for ix in range(num_verts_x):
                x_norm = ix / float(grid_size)
                # Derivadas parciais dpy/dx e dpy/dz
                df_dx = (math.cos(x_norm * math.pi * 6.0) * (math.pi * 6.0 / world_size) * math.cos(y_norm * math.pi * 6.0) * 4.0 +
                         math.cos(x_norm * math.pi * 14.0) * (math.pi * 14.0 / world_size) * 1.5)
                df_dz = (-math.sin(x_norm * math.pi * 6.0) * math.sin(y_norm * math.pi * 6.0) * (math.pi * 6.0 / world_size) * 4.0 -
                         math.sin(y_norm * math.pi * 18.0) * (math.pi * 18.0 / world_size) * 1.2)
                # Normal = normalize(-df_dx, 1, -df_dz)
                nx, ny, nz = -df_dx, 1.0, -df_dz
                len_n = math.sqrt(nx * nx + ny * ny + nz * nz)
                nx /= len_n
                ny /= len_n
                nz /= len_n
                f.write(f"vn {nx:.5f} {ny:.5f} {nz:.5f}\n")

        # Faces (f)
        for iy in range(grid_size):
            row_start = iy * num_verts_x + 1
            next_row_start = (iy + 1) * num_verts_x + 1
            for ix in range(grid_size):
                v00 = row_start + ix
                v10 = row_start + ix + 1
                v01 = next_row_start + ix
                v11 = next_row_start + ix + 1

                # Dois triangulos por quad com orientacao CCW
                # Triangulo 1: v00 -> v01 -> v10
                f.write(f"f {v00}/{v00}/{v00} {v01}/{v01}/{v01} {v10}/{v10}/{v10}\n")
                # Triangulo 2: v10 -> v01 -> v11
                f.write(f"f {v10}/{v10}/{v10} {v01}/{v01}/{v01} {v11}/{v11}/{v11}\n")

    print(f"Sucesso! Malha gravada em: {output_path}")

if __name__ == "__main__":
    out = "tests/procedural_1m.obj"
    if len(sys.argv) > 1:
        out = sys.argv[1]
    generate_procedural_terrain(out, grid_size=708, world_size=100.0)
