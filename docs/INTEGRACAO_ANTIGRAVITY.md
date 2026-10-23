# ARBORIA AI — Instrução direta para o Antigravity

## Missão
Integre o `tools/arboria_ai` recebido ao repositório oficial, configure a conexão **real** com o Ollama local e os testes **reais** de C++/GLSL/Godot. Execute um ciclo completo de proposta, compilação, renderização, medição e aprovação/rejeição. Não reescreva o motor. Não execute auditorias gerais nem afirme que o Ollama calculou na GPU: o LLM sugere alterações; compute shaders e compiladores realizam cálculos; benchmarks decidem.

1. Preserve o branch e as alterações existentes. Instale o módulo apenas em `tools/arboria_ai`.
2. Confirme `http://127.0.0.1:11434/api/tags` e escolha pelo nome exato um modelo de programação instalado. Não baixe um modelo grande sem necessidade; na RTX 3050 de 6 GB modelos maiores podem utilizar RAM/CPU, causando latência.
3. Configure `tools/arboria_ai/config.json` com comandos de compilação e testes **não permissivos**. O gate anterior permite 2 erros, 60 RIDs vazados e reutiliza PNGs antigos: corrija essas condições antes de usá-lo como teste de aceitação. Um simples retorno 0 desse gate antigo **não** é suficiente.
4. Crie/adapte um runner do benchmark que escreva `artifacts/aeoc_metrics.json` após uma execução **real e nova** em hardware. O JSON precisa conter `gpu_p95_ms`, `frame_p95_ms`, `vram_mb`, `visible_clusters`, `visual_error`. Configure o comando em `benchmark.argv`. Os frames medidos devem ter geometria efetivamente visível (zero clusters reprova). **`visual_error` deve ser produzido por comparação real com captura de referência; não invente números.**
5. Execute `python -m tools.arboria_ai.cli status`, depois um ciclo **dirigido** no shader global:

   ```powershell
   python -m tools.arboria_ai.cli propose --target project/shaders/cull_clusters_global.glsl --goal "eliminar procura linear de instancias mantendo todos os clusters e o culling correto" --model MODELO_INSTALADO
   python -m tools.arboria_ai.cli evaluate --id ID_RETORNADO
   python -m tools.arboria_ai.cli history
   ```

6. Verifique o `candidate.diff` em `%USERPROFILE%\.arboria_ai\...\proposals\ID\candidate.diff`. Somente se o teste A/B tiver retornado `PASSED`, execute `python -m tools.arboria_ai.cli promote --id ID_RETORNADO`. Isso aplica o código **sem commit**, para revisão e commit posteriores.
7. Em cada alteração permitida, o Ollama recebe lições de tentativas aprovadas e rejeitadas do **mesmo arquivo**. Não confunda esse histórico com treinamento dos pesos do modelo. Preservar o SQLite permite recuperação e, futuramente, preparar um dataset para fine-tuning supervisionado.
8. Não use `--promote-on-pass` antes de confirmar isolamento de testes, qualidade das evidências e proteção dos gates. Mesmo em uma worktree, compilar código sugerido por LLM **não é sandbox de segurança**. Para alto grau de autonomia, execute os compiladores/benchmarks em VM ou contêiner sem privilégios, com rede restrita e recursos limitados.
9. Corrija problemas de runtime antes de pedir otimizações: se o benchmark registrar `visible_clusters = 0`, a otimização fica bloqueada. Conserte primeiro o caminho que desenha as malhas, repetindo os testes reais.
10. Não bloqueie uma implementação importante por ganho de FPS de 3% se for **correção de funcionalidade**: este controlador é para experimentos de otimização de desempenho. Bugs de renderização devem ser corrigidos e aprovados pelos testes de correção pertinentes.

**EXECUTE, COMPILE, RENDERIZE, MEÇA, COMPARE E REGISTRE.** Não declare melhora sem baseline válida e amostras reais.
