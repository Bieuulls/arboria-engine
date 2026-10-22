class_name ArboriaAssetImporter
extends RefCounted

## ARBORIA ENGINE — ASSET IMPORTER & BAKER INTEGRATOR
## Converte modelos 3D (.obj) em malhas virtuais (.vgmesh) com hierarquia Nanite DAG,
## clusters otimizados e assinatura criptográfica de integridade ARB-SIGN.

const BAKER_RELATIVE_PATH = "../bin/vg_baker_cli.exe"

## Converte um arquivo .obj para .vgmesh
## Exemplo: ArboriaAssetImporter.bake_obj_to_vgmesh("res://assets/my_mesh.obj", "res://assets/my_mesh.vgmesh")
static func bake_obj_to_vgmesh(p_input_obj_path: String, p_output_vgmesh_path: String) -> Dictionary:
	var global_in = ProjectSettings.globalize_path(p_input_obj_path)
	var global_out = ProjectSettings.globalize_path(p_output_vgmesh_path)

	if not FileAccess.file_exists(p_input_obj_path):
		push_error("[ArboriaAssetImporter] Arquivo de entrada nao encontrado: " + p_input_obj_path)
		return {"success": false, "error": "Input file not found"}

	var exe_path = ProjectSettings.globalize_path("res://" + BAKER_RELATIVE_PATH)
	if not FileAccess.file_exists(exe_path):
		# Fallback para caminho absoluto do projeto
		exe_path = "d:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/bin/vg_baker_cli.exe"

	if not FileAccess.file_exists(exe_path):
		push_error("[ArboriaAssetImporter] Executavel vg_baker_cli.exe nao encontrado!")
		return {"success": false, "error": "Baker executable not found"}

	print("[ArboriaAssetImporter] Iniciando bake de geometria virtualizada:")
	print(" - Entrada: ", global_in)
	print(" - Saida:   ", global_out)

	var output = []
	var args = [global_in, global_out, "--verify"]
	var exit_code = OS.execute(exe_path, args, output, true)

	var log_str = "\n".join(output)
	if exit_code == 0:
		print("[ArboriaAssetImporter] Bake concluido com sucesso absoluto!")
		return {
			"success": true,
			"output_path": p_output_vgmesh_path,
			"log": log_str
		}
	else:
		push_error("[ArboriaAssetImporter] Falha no bake (Codigo: %d):\n%s" % [exit_code, log_str])
		return {
			"success": false,
			"error": "Baker failed with exit code %d" % exit_code,
			"log": log_str
		}

## Valida um arquivo .vgmesh existente
static func verify_vgmesh(p_vgmesh_path: String) -> bool:
	var global_path = ProjectSettings.globalize_path(p_vgmesh_path)
	var exe_path = "d:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/bin/vg_baker_cli.exe"
	var output = []
	var exit_code = OS.execute(exe_path, ["--verify-only", global_path], output, true)
	return exit_code == 0
