# ARBORIA ENGINE — Avaliação de Smart Pointers (shared_ptr → unique_ptr)

**Prioridade:** BAIXA  
**Status:** Planejado (não iniciado)  
**Data:** 2026-11-02

---

## 1. Uso Atual de shared_ptr

| Local | Tipo | Proprietários | Justificativa atual |
|-------|------|---------------|---------------------|
| `InstanceRecord.mutable_overlay` | `shared_ptr<MutableGeometryOverlay>` | InstanceRegistry + possivelmente caller | Overlay pertence à instância; único dono lógico |
| `MeshRegistry.m_mesh_pool` slots | `RegisteredMeshInfo` com `shared_ptr<VGMeshResource>` | MeshRegistry + callers que pedem `get_mesh_resource()` | Recurso de malha compartilhado entre instâncias |
| `VGRuntime.get_mesh_by_handle()` | `shared_ptr<VGMeshResource>` | Callers via GDExtension | Acesso compartilhado a dados de malha |
| `MutableGeometryOverlay.m_regions` | `unordered_map<uint32_t, MutableRegion>` (valor) | Overlay proprietário | Único dono, OK |

---

## 2. Análise por Caso

### 2.1 `MutableGeometryOverlay` (shared_ptr → unique_ptr recomendado)

**Problema:** `InstanceRecord` armazena `shared_ptr<MutableGeometryOverlay>`. Como cada instância tem seu próprio overlay (ou nullptr), não há compartilhamento entre instâncias. O `shared_ptr` adiciona overhead de contagem atômica desnecessário.

**Recomendação:** Mudar para `unique_ptr<MutableGeometryOverlay>` em `InstanceRecord`. Métodos `get_or_create_mutable_overlay()` e `get_mutable_overlay()` retornam `MutableGeometryOverlay*` ou `shared_ptr` para compatibilidade com callers existentes, mas internamente usam `unique_ptr`.

**Risco:** Baixo. Callers que precisam de shared ownership podem receber `shared_ptr` construído a partir do `unique_ptr` (com `shared_from_this` ou wrapper).

### 2.2 `VGMeshResource` (manter shared_ptr)

**Problema:** Recursos de malha são compartilhados entre múltiplas instâncias que usam a mesma malha. O `shared_ptr` é apropriado aqui.

**Recomendação:** Manter `shared_ptr<VGMeshResource>`. Avaliar se `weak_ptr` seria melhor para caches (evitar retenção de memória quando ninguém usa).

**Risco:** Nenhuma mudança necessária.

### 2.3 `GenerationalPool<InstanceRecord>` (avaliar)

**Problema:** O pool armazena `InstanceRecord` por valor. Se `InstanceRecord` contém `unique_ptr`, o pool precisa suportar move (já suporta via `std::move` em `allocate()`).

**Recomendação:** Viável. O `GenerationalPool` já usa `std::move(item)` em `allocate()`.

---

## 3. Impacto Esperado

| Métrica | Antes | Depois (estimado) |
|---------|-------|-------------------|
| Overhead atômico por instância | ~1 contagem shared_ptr | 0 (unique_ptr) |
| Previsibilidade de memória | Moderada | Alta |
| Risco de referência circular | Baixo (não há) | Baixo |
| Complexidade de refatoração | — | Médio (3-5 dias) |

---

## 4. Próximos Passos

1. Auditar todos os `shared_ptr` no código nativo
2. Identificar casos de único dono (candidatos a `unique_ptr`)
3. Implementar mudança em `InstanceRecord.mutable_overlay`
4. Atualizar callers de `get_or_create_mutable_overlay` / `get_mutable_overlay`
5. Executar testes 1-30 para verificar regressão
6. Rodar ASan/UBSan para confirmar sem vazamentos
