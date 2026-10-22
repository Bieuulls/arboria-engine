# Evidência complementar — despacho e telemetria GPU (21/10/2026)

Inspeção estática de `project/scripts/vg_gpu_pipeline.gd`, linhas 600–665:

- O código limpa 20 bytes do contador a partir do offset 4 (`buffer_clear(counter_buf, 4, 20)`), preservando o campo `vertex_count` no offset 0. A premissa de 384 vértices é explicitada em comentário, mas o valor inicial e a compatibilidade com o pipeline precisam de verificação de execução.
- O despacho é montado por `compute_list_begin`, `compute_list_bind_compute_pipeline`, `compute_list_bind_uniform_set`, `compute_list_dispatch(groups_x,1,1)` e `compute_list_end`. Isso comprova a existência de uma rota de submissão, não sua execução bem-sucedida na GPU.
- `capture_timestamp` delimita o despacho e `poll_timestamps` lê tempos GPU; é necessária uma captura gráfica para comprovar timestamps válidos, ausência de falhas e custo medido.
- `poll_stats_async` usa `buffer_get_data_async` para 24 bytes; a leitura é assíncrona na API, mas periodicidade, sincronização interna e ausência de stalls dependem de perfilamento.
- A contagem de triângulos é lida no offset 16 e a de clusters avaliados no offset 20; esses valores são contadores declarados pelo pipeline, ainda não validados contra captura independente.

**Conclusão restrita:** existe código de despacho compute, coleta assíncrona e telemetria; ainda falta evidência de execução Vulkan em janela, da dependência correta entre compute e indirect draw, e de resultados A/B/C/D. Nenhum arquivo do motor foi alterado nesta nota.

## Verificação de disponibilidade Vulkan (21/10/2026)

ulkaninfo --summary executou com código de saída 0. O relatório bruto está em ulkaninfo_summary_20261021.txt. A enumeração identificou NVIDIA GeForce RTX 3050, driver NVIDIA 617.42, API Vulkan 1.4.351. O loader também informou aviso de consulta ao registro de manifests de layers; a enumeração terminou normalmente. **Isso comprova dispositivo Vulkan disponível no Windows, mas não comprova que a cena ARBORIA, o compute ou o indirect draw funcionem.** A falha anterior em modo headless não pode ser extrapolada para modo gráfico.

## Inspeção adicional de fluxo GPU (21/10/2026)

Inspeção estática de `project/scripts/vg_gpu_pipeline.gd`:

- Linhas 603–616: limpa contadores e textura, registra timestamps e despacha `compute_list_dispatch`. Isto prova que existe código para submeter compute; não prova que o dispatch foi executado em dispositivo Vulkan durante um frame real.
- Linhas 627–643: lê timestamps via `get_captured_timestamp_gpu_time` e calcula diferença em microssegundos. A instrumentação é de tempo GPU, mas falta log de execução gráfica que valide os timestamps, seus pares por frame e valores.
- Linhas 645–663: telemetria usa `buffer_get_data_async` e callback; nesta função não foi encontrada leitura síncrona. É necessário auditar os demais caminhos antes de afirmar ausência global de bloqueios.
- Linhas 917–922 e 980–985: existem duas chamadas explícitas a `draw_list_draw_indirect`, consumindo `counter_buf` com offset 0, um comando e stride 16. Há caminho de consumo de argumentos indiretos implementado no código. Falta prova de execução, sincronização efetiva e conteúdo visual correto.
- Linhas 905–909: renderização indireta é condicional a `enable_indirect_draw`; modo de depuração pode zerar `instance_count`. Os benchmarks precisam registrar esses flags para evitar comparação inválida.

**Conclusão restrita:** a implementação contém comandos reais de API de compute, timestamps, readback assíncrono e desenho indireto; a integração GPU→imagem final continua sem validação instrumental em sessão Vulkan com janela. Nenhum FPS, ganho ou qualidade visual é inferido desta leitura.

## Novo achado: uso do buffer de argumentos indiretos

`project/scripts/vg_gpu_pipeline.gd:274` cria `counter_buf` via `rd.storage_buffer_create(24, cnt_bytes, RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)`. O mesmo RID é passado para `rd.draw_list_draw_indirect` em `:921` e `:984`. **Risco de compatibilidade/validação:** a flag indicada nominalmente para dispatch indireto está sendo usada em draw indireto; confirmar no contrato exato do RenderingDevice 4.7.2 se o recurso recebe `VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT` e se é válido para ambos. Verificar com validação Vulkan em execução gráfica; ainda não classificar como falha comprovada.

Não há chamada explícita `compute_list_add_barrier` no arquivo, conforme busca textual; isso isoladamente não prova falta de sincronização, pois `compute_list_end`/transições de lista e backend podem inserir barreiras. Exigir captura ou validação de hazards compute→draw antes de concluir.

## Confirmação adicional dos gates de desenho (21/10/2026)

Inspeção direta das linhas 895–922 e 958–985 confirma que ambos os caminhos de desenho exigem RIDs válidos e nable_indirect_draw; debug_force_zero_instances limpa os 4 bytes em offset 4 antes do draw. O despacho de compute nas linhas 603–615 zera offsets 4–23, preservando o campo de 4 bytes em offset 0. O comando indireto usa stride 16 e um único draw. **Consequência para o teste:** capturar counter_buf imediatamente antes de cada draw e comparar instance_count com o número de clusters selecionados, repetindo com debug_force_zero_instances=true e com culling desligado. A inspeção confirma a ligação por RID e offsets; não comprova a validade do buffer Vulkan, a ordem efetiva GPU ou pixels renderizados.



## Capturas gráficas adicionais (21/10/2026, 16:54)
Quatro PNGs produzidos pelo script `project/scripts/test_negative_probe.gd` existem na raiz e têm timestamp 16:54:19. Inspeção independente por Pillow: todos 1280×720; referência visível (`diag_frame2_ref_visible.png`) tem 2 cores; referência oculta (`diag_frame3_ref_hidden.png`) e frame seguinte (`diag_frame4.png`) têm 1 cor cada e são idênticos pixel a pixel. Captura imediatamente após `pipeline.render_to_viewport` (`diag_frame3_after_arboria.png`) tem 1808 cores e difere da imagem com referência oculta no retângulo x=349..930, y=95..624. Isso é evidência de escrita visual transitória no viewport durante a chamada, mas **não comprova** apresentação persistente no frame seguinte, correção geométrica, culling GPU, execução Vulkan validada, sincronização ou ganho de desempenho. O desenho não persiste no frame 4, segundo a comparação de imagens. Atribuição causal completa exige log de execução associado à captura e instrumentação de GPU.
