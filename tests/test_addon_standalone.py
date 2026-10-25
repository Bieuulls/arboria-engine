#!/usr/bin/env python3
"""
ARBORIA ENGINE — TESTE DE INSTALAÇÃO STANDALONE DO ADDON (FASE 5.5)
Valida que uma cópia isolada de 'addons/arboria/' em um projeto Godot novo e limpo
carrega e ativa o plugin com sucesso, sem dependências ausentes de 'tools/' ou 'bench/'.
"""

import os
import sys
import shutil
import tempfile
import subprocess
import glob
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

def find_godot_bin():
    if "GODOT_BIN" in os.environ and os.path.isfile(os.environ["GODOT_BIN"]):
        return os.environ["GODOT_BIN"]
    candidates = [
        shutil.which("godot"),
        shutil.which("godot4"),
        shutil.which("godot_console.exe"),
        str(REPO_ROOT / "bin" / "godot_console.exe"),
        str(REPO_ROOT / "bin" / "godot.exe"),
    ]
    localapp = os.environ.get("LOCALAPPDATA", "")
    if localapp:
        candidates.extend(glob.glob(os.path.join(localapp, "Microsoft", "WinGet", "Packages", "GodotEngine.GodotEngine*", "*console.exe")))
        candidates.extend(glob.glob(os.path.join(localapp, "Microsoft", "WinGet", "Packages", "GodotEngine.GodotEngine*", "Godot*.exe")))
    for c in candidates:
        if c and os.path.isfile(c):
            return os.path.normpath(c)
    raise RuntimeError("Executável do Godot não encontrado.")


def main():
    print("==================================================================")
    print(" [FASE 5.5] TESTE DE INSTALAÇÃO STANDALONE DO ADDON ARBORIA       ")
    print("==================================================================")

    godot_bin = find_godot_bin()
    print(f"Godot Binário: {godot_bin}")

    source_addon = REPO_ROOT / "addons" / "arboria"
    if not source_addon.is_dir():
        print(f"[FALHA] Diretório source do addon não encontrado: {source_addon}")
        return 1

    temp_dir = Path(tempfile.mkdtemp(prefix="arboria_standalone_test_"))
    print(f"Diretório temporário isolado: {temp_dir}")

    try:
        # 1. Cria projeto Godot mínimo
        project_godot = temp_dir / "project.godot"
        project_content = (
            '; Engine configuration file.\n'
            'config_version=5\n\n'
            '[application]\n'
            'config/name="Test Standalone Arboria"\n'
            'run/main_scene="res://Main.tscn"\n'
            'config/features=PackedStringArray("4.7", "Forward Plus")\n\n'
            '[editor_plugins]\n'
            'enabled=PackedStringArray("res://addons/arboria/plugin.cfg")\n'
        )
        project_godot.write_text(project_content, encoding="utf-8")

        # 2. Copia addons/arboria
        dest_addon = temp_dir / "addons" / "arboria"
        shutil.copytree(source_addon, dest_addon)
        print("Cópia de 'addons/arboria' concluída.")

        # Garante que a dll nativa esteja presente em addons/arboria/bin se existir compilada
        dest_bin = dest_addon / "bin"
        dest_bin.mkdir(parents=True, exist_ok=True)
        native_dll = REPO_ROOT / "project" / "bin" / "libarboria_native.dll"
        if not native_dll.exists():
            native_dll = REPO_ROOT / "native" / "renderer" / "build" / "libarboria_native.dll"
        if native_dll.exists():
            shutil.copy2(native_dll, dest_bin / "libarboria_native.dll")
            print("Binário nativo sincronizado em addons/arboria/bin/libarboria_native.dll.")

        # 3. Cria Main.gd e Main.tscn
        main_gd = temp_dir / "Main.gd"
        main_gd_content = (
            'extends Node\n\n'
            'func _ready() -> void:\n'
            '    print("[STANDALONE TEST] Inicializando carregamento do addon...")\n'
            '    var inst_script = load("res://addons/arboria/nodes/arboria_instance_3d.gd")\n'
            '    if inst_script == null:\n'
            '        printerr("[ERRO] Falha ao carregar arboria_instance_3d.gd")\n'
            '        get_tree().quit(1)\n'
            '        return\n'
            '    var node = inst_script.new()\n'
            '    if node == null:\n'
            '        printerr("[ERRO] Falha ao instanciar ArboriaInstance3D")\n'
            '        get_tree().quit(1)\n'
            '        return\n'
            '    print("[STANDALONE TEST] ArboriaInstance3D instanciado com sucesso!")\n'
            '    node.free()\n'
            '    print("[STANDALONE TEST] SUCESSO: Addon 100% standalone e funcional.")\n'
            '    get_tree().quit(0)\n'
        )
        main_gd.write_text(main_gd_content, encoding="utf-8")

        main_tscn = temp_dir / "Main.tscn"
        main_tscn_content = (
            '[gd_scene load_steps=2 format=3]\n\n'
            '[ext_resource type="Script" path="res://Main.gd" id="1_script"]\n\n'
            '[node name="Main" type="Node"]\n'
            'script = ExtResource("1_script")\n'
        )
        main_tscn.write_text(main_tscn_content, encoding="utf-8")

        # 4. Inicializa o projeto uma vez em modo editor headless para importar os recursos
        print("Importando projeto Godot headless...")
        init_cmd = [godot_bin, "--headless", "--editor", "--quit", "--path", str(temp_dir)]
        subprocess.run(init_cmd, capture_output=True, timeout=20)

        # 5. Executa Godot headless executando a cena principal
        cmd = [
            godot_bin,
            "--headless",
            "--path", str(temp_dir)
        ]
        print(f"Executando Godot: {' '.join(cmd)}")
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        stdout = res.stdout
        stderr = res.stderr

        print("--- SAÍDA DO GODOT ---")
        print(stdout)
        if stderr:
            print("--- STDERR ---")
            print(stderr)

        if res.returncode != 0:
            print(f"[FALHA] Godot retornou código {res.returncode}")
            return 1

        if "[STANDALONE TEST] SUCESSO" not in stdout:
            print("[FALHA] Confirmação de sucesso não encontrada na saída.")
            return 1

        print("==================================================================")
        print(" [APROVADO] TESTE DE INSTALAÇÃO STANDALONE DO ADDON PASSOU!     ")
        print("==================================================================")
        return 0

    finally:
        try:
            shutil.rmtree(temp_dir, ignore_errors=True)
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
