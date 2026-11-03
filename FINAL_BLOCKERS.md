# ARBORIA ENGINE — FINAL BLOCKERS

Problemas ainda abertos e verificáveis.

---

## Bloqueios Ativos

| ID | Descrição | Severidade | Status | Dependências |
|----|-----------|------------|--------|--------------|
| B-001 | Critério 3 (GDExtension funcional): não há Godot 4.7 runtime disponível no ambiente | Alta | NOT_RUN | Ambiente externo |
| B-002 | Critério 11 (PBR e sombras corretos): não há GPU disponível para teste visual | Alta | NOT_RUN | Ambiente externo |
| B-003 | Nada commitado — não é repositório git (sem histórico de commits) | Média | NOT_APPLICABLE | Nenhuma |

## Bloqueios Resolvidos

| ID | Descrição | Resolução |
|----|-----------|-----------|
| B-000 | ASan heap-use-after-free: VGRuntime::shutdown() acessava ArboriaMeshRegistry após destruição do estático | Removido `ArboriaMeshRegistry::instance().clear()` de `VGRuntime::shutdown()` em `arboria_runtime.cpp` |
