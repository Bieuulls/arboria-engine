# Testes reais — 21/10/2026

Comando: `python tests/test_suite.py` na raiz oficial. Resultado: 17 verificações aprovadas; saída integral em `testes_log.txt`. Cobertura: Baker, OBJ pequeno/denso, entradas inválidas, ARBORIA2 v2, DAG e offsets, corrupção de cabeçalho/payload e LOD0 lossless. Fixture densa reportou 367 clusters, 9 LODs, 27 grupos DAG (resultado de teste, não benchmark).

Godot 4.7.2 headless por caminho absoluto: exit 0, mas erro em `vg_gpu_pipeline.gd:75` de RenderingDevice Vulkan indisponível. Resultado GPU inconclusivo. `godot` pelo PATH não encontrado. Não houve teste gráfico Vulkan reproduzível, captura de frame, medição de FPS/VRAM, teste A/B/C/D nem verificação de sombras/PBR.

Próximos testes: inicializar com Vulkan em janela; registrar GPU timestamps, counters e frame capture; variar câmera/LOD e conferir geometria; medir vazamentos; testar módulo C++ compilado; comparar quatro configurações sob parâmetros fixos.


## Capturas gráficas adicionais (21/10/2026, 16:54)
Quatro PNGs produzidos pelo script `project/scripts/test_negative_probe.gd` existem na raiz e têm timestamp 16:54:19. Inspeção independente por Pillow: todos 1280×720; referência visível (`diag_frame2_ref_visible.png`) tem 2 cores; referência oculta (`diag_frame3_ref_hidden.png`) e frame seguinte (`diag_frame4.png`) têm 1 cor cada e são idênticos pixel a pixel. Captura imediatamente após `pipeline.render_to_viewport` (`diag_frame3_after_arboria.png`) tem 1808 cores e difere da imagem com referência oculta no retângulo x=349..930, y=95..624. Isso é evidência de escrita visual transitória no viewport durante a chamada, mas **não comprova** apresentação persistente no frame seguinte, correção geométrica, culling GPU, execução Vulkan validada, sincronização ou ganho de desempenho. O desenho não persiste no frame 4, segundo a comparação de imagens. Atribuição causal completa exige log de execução associado à captura e instrumentação de GPU.
