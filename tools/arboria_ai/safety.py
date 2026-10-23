"""Strictly bound model output to one allowlisted source file and literal edits."""
from __future__ import annotations
import difflib
import fnmatch
import hashlib
import json
from pathlib import Path, PurePosixPath

BLOCKED_PARTS = {'.git', '.github', 'tests', 'test', 'gates', 'bench', 'docs', 'artifacts', 'secrets', '.env'}
ALLOWED_SUFFIXES = {'.cpp', '.h', '.hpp', '.c', '.glsl', '.gd'}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalize_target(path: str, allowlist: list[str]) -> str:
    if not path or '\\' in path or path.startswith('/') or ':' in path:
        raise ValueError('O caminho deve ser relativo ao repositório, usando /.')
    p = PurePosixPath(path)
    if any(part in {'', '.', '..'} or part.lower() in BLOCKED_PARTS for part in p.parts):
        raise ValueError('Caminho protegido ou inválido.')
    if p.suffix.lower() not in ALLOWED_SUFFIXES:
        raise ValueError('Extensão fora do conjunto permitido para C++/GLSL/GDScript.')
    if not any(fnmatch.fnmatch(path, pat) for pat in allowlist):
        raise ValueError('Arquivo fora da lista explícita de edição.')
    return str(p)


def resolve_target(root: Path, path: str, allowlist: list[str]) -> Path:
    rel = normalize_target(path, allowlist)
    repo = root.resolve()
    f = (repo / rel).resolve()
    if not f.is_relative_to(repo) or not f.is_file():
        raise ValueError('Arquivo ausente ou caminho fora da raiz.')
    return f


def apply_literal_edits(original: str, edits: list[dict], target: str, max_edits: int = 4,
                        max_added_chars: int = 10000) -> str:
    if not isinstance(edits, list) or not 1 <= len(edits) <= max_edits:
        raise ValueError('A resposta deve ter de 1 a %d alterações.' % max_edits)
    result = original
    additions = 0
    for edit in edits:
        if not isinstance(edit, dict) or edit.get('path') != target:
            raise ValueError('Modelo tentou alterar outro arquivo.')
        old, new = edit.get('old_text'), edit.get('new_text')
        if not isinstance(old, str) or not isinstance(new, str) or not old.strip():
            raise ValueError('Trecho original/válido ausente.')
        if old == new:
            raise ValueError('Alteração vazia.')
        if result.count(old) != 1:
            raise ValueError('Trecho original não é único ou não existe. Encontrado: %d. Trecho: %r' % (result.count(old), old))
        additions += len(new)
        if additions > max_added_chars:
            raise ValueError('Alterações maiores que o limite permitido.')
        result = result.replace(old, new, 1)
    if result == original:
        raise ValueError('Nenhuma alteração efetiva.')
    return result


def unified_patch(path: str, before: str, after: str) -> str:
    return ''.join(difflib.unified_diff(before.splitlines(keepends=True),
                  after.splitlines(keepends=True), fromfile='a/'+path, tofile='b/'+path))


def safe_json_load(s: str) -> dict:
    data = json.loads(s)
    if not isinstance(data, dict) or not isinstance(data.get('edits'), list):
        raise ValueError('Resposta do modelo sem alterações estruturadas.')
    return data
