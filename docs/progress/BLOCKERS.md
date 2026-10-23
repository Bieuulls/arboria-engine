# ARBORIA ENGINE — REGISTRO DE BLOQUEIOS E LIMITAÇÕES

Este documento rastreia bloqueios técnicos concretos, limitações de API e causas de falha identificadas durante a execução dos Gates.

---

## Bloqueios Ativos

*Nenhum bloqueio técnico intransponível identificado no momento.*

---

## Histórico de Resoluções Técnicas

1. **Auto-dependência de textura no grafo do RenderingDevice (Hi-Z Downsample):**
   - *Sintoma:* `ERROR: Command can't have itself as a dependency. at: _add_command_to_graph`
   - *Causa:* Tentar ler de `hiz_texture` (amostrada) e escrever em uma fatia `hiz_mip_views[m]` da mesma textura no mesmo comando.
   - *Solução Técnica:* Alocação de `hiz_scratch_texture` independente e cópia direta de mips via `texture_copy(scratch, hiz, ..., 0, m, 0, 0)`.
   - *Status:* Resolvido e comprovado em hardware NVIDIA RTX 3050.

2. **Detecção de escala espelhada (Determinante Negativo):**
   - *Sintoma:* Normais invertidas e winding incorreto em instâncias com escala negativa (ex: `scale.x = -1.0`).
   - *Causa:* Inversão de orientação poligonal no espaço de projeção.
   - *Solução Técnica:* Detecção em C++ (`det < 0`), flag `FLAG_MIRRORED = 0x4` e ajuste de winding no rasterizador.
   - *Status:* Resolvido e validado.
