# ARBORIA Ollama Evolution Engine v0.1

**Um auxiliar de engenharia real** para o ARBORIA ENGINE: chama Ollama, recebe uma edição de código limitada, salva um diff, testa a edição em `git worktree` isolada, compara métricas A/B e registra aprovações/reprovações no SQLite. É um *otimizador assistido por LLM*, **não** uma nova GPU/IA treinada automaticamente.

## Instalação no Windows

1. Instale e inicie o [Ollama](https://ollama.com/download). Em um terminal, confirme `ollama list`. Se o serviço não estiver iniciado: `ollama serve` (não execute duas instâncias do servidor).
2. Extraia este ZIP. No PowerShell execute:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\INSTALL_WINDOWS.ps1 -Repo 'D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL'
   cd 'D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL'
   python -m tools.arboria_ai.cli status
   ```

3. Edite `tools/arboria_ai/config.json`, inserindo em `ollama.model` o **nome exato de um modelo listado**. O modelo não é baixado automaticamente.
4. Configure `checks` e `benchmark.argv`, pois **avaliações reprovam quando esses comandos não estão configurados**. Essa escolha evita declarar progresso com compilação/benchmark inexistentes. O Antigravity deve conectá-los aos comandos verdadeiros do ARBORIA e corrigir seus gates permissivos anteriores.

Exemplo **apenas do formato** dos comandos (ajuste executáveis e caminhos reais; não é prova GPU):

```json
"checks": [
  {"name": "native-build", "argv": ["powershell.exe", "-NoProfile", "-File", "tools/gates/build_native.ps1"], "timeout_seconds": 900},
  {"name": "strict-godot-regression", "argv": ["powershell.exe", "-NoProfile", "-File", "tools/gates/run_gate.ps1", "-Stage", "02"], "timeout_seconds": 900}
],
"benchmark": {
  "argv": ["powershell.exe", "-NoProfile", "-File", "tools/aeoc_run_actual_benchmark.ps1"],
  "output_json": "artifacts/aeoc_metrics.json",
  "repetitions": 3,
  "timeout_seconds": 3600
}
```

**Atenção:** o gate legado `run_gate.ps1` precisa ser corrigido antes de ser considerado *strict*. O exemplo de `tools/aeoc_run_actual_benchmark.ps1` é um nome de integração que o Antigravity deverá implementar com as cenas e métricas reais existentes; esse script **não está neste pacote**. Não use `evaluate` antes de finalizar os dois conectores.

## Uso

```powershell
cd D:\ARBORIA_ENGINE\ARBORIA_ENGINE_OFFICIAL
python -m tools.arboria_ai.cli status

python -m tools.arboria_ai.cli propose --model NOME_DO_OLLAMA --target project/shaders/cull_clusters_global.glsl --goal "Reduzir custo de localizar a instância do cluster, preservando a geometria"

python -m tools.arboria_ai.cli evaluate --id ID_DO_EXPERIMENTO

python -m tools.arboria_ai.cli history

python -m tools.arboria_ai.cli promote --id ID_DO_EXPERIMENTO
```

Para arquivo grande, limite o contexto sem truncar arbitrariamente segmentos:

```powershell
python -m tools.arboria_ai.cli propose --model NOME --target project/scripts/arboria_native_pipeline.gd --lines 100:300 --goal "reduzir reconstrução das matrizes de transform sem alterar objetos estáticos"
```

Após instalar benchmarks válidos, o ciclo limitado pode consultar o Ollama até cinco vezes e testar cada candidato:

```powershell
python -m tools.arboria_ai.cli cycle --model NOME --target project/shaders/cull_clusters_global.glsl --goal "otimizar lookup GPU sem regressão geométrica" --attempts 3
```

Sem `--promote-on-pass`, ele apenas sugere/testa e deixa o candidato aprovado para revisão. O sinalizador `--promote-on-pass` aplica uma proposta **somente** após os testes configurados a aprovarem; **não cria commit**.

## Proteções

- Modelo recebe somente um arquivo alvo (ou trecho de contexto) por proposta. Permite edições literais de no máximo 4 blocos, com tamanho limitado.
- Não aceita alterações em testes, gates, benchmarks, documentos, `.git`, código fora da lista de permissão nem caminhos `..`.
- Não executa comandos fornecidos pelo modelo. Apenas comandos estáticos definidos pelo engenheiro em `config.json`.
- Git worktrees separadas para A/B; valida hash do arquivo, SHA do commit e se o arquivo alvo foi alterado localmente.
- Em cada execução de benchmark, remove o JSON anterior antes do comando de teste, rejeitando artefatos antigos.
- Exige no mínimo 3 repetições e interleia baseline/candidato.
- Falha se GPU, frame, VRAM, comparação visual ou clusters visíveis estiverem ausentes/inválidos.
- Exige clusters visíveis positivos para impedir benchmark de draw vazio; **não reprova automaticamente quando o culling reduz a contagem**, pois isso pode ser o ganho desejado. A equivalência precisa ser medida pela imagem real (`visual_error`) e pelos testes geométricos. Em cenários que exigem paridade exata de clusters, ative `require_cluster_count_parity`.
- Promove somente candidato `PASSED` e não mexe no histórico Git.

## Limites reais da V0.1

Este pacote foi testado no ambiente Python disponível, não na máquina Windows nem em uma instância real do Ollama. A conexão `/api/chat` e o protocolo JSON seguem a API oficial; a integração com a RTX 3050, os testes de cena e a geração de métricas do Godot dependem de configurar o projeto local.

**Não é treinamento de pesos de IA.** O SQLite preserva histórico e lessons learned para orientar novas consultas; fine-tuning exige um projeto adicional, com dados limpos, validação independente e hardware apropriado.

**Aviso de segurança:** worktrees separam alterações no Git, mas **não isolam execução do código**. Builds e testes de código gerado por LLM devem rodar em ambientes de confiança limitada, preferencialmente VM/contêiner isolado, antes de ativar promoção automática.

Arquivos de memória e evidência ficam, por padrão, em `%USERPROFILE%\.arboria_ai\<hash-do-repositorio>`, e não são adicionados ao Git.

Mais detalhes: `docs/INTEGRACAO_ANTIGRAVITY.md`.

## Adaptadores incluídos para evidência (não inventam dados)

- `python -m tools.arboria_ai.bench_csv_adapter`: calcula p95 real por cenário/variante/instâncias a partir do CSV, mas **reprova** se faltar o contador customizado `visible_clusters`. Requer um JSON de erro visual derivado de captura real.
- `python -m tools.arboria_ai.visual_compare`: compara duas imagens PNG capturadas sob câmera, projeção, iluminação, LOD e resolução idênticos. Produz `visual_error` como erro médio absoluto RGB normalizado. **Não comprova anatomia, equivalência de sombras ou geometria sozinho**; combine com testes de depth/coverage e DAG apropriados.

Exemplo:

```powershell
python -m pip install -r requirements-optional.txt
python -m tools.arboria_ai.visual_compare --reference artifacts/ref.png --candidate artifacts/arboria.png --output artifacts/visual.json
python -m tools.arboria_ai.bench_csv_adapter --csv bench/results/raw.csv --scenario dense_rock --variant arboria --instances 80 --visual-error-json artifacts/visual.json --output artifacts/aeoc_metrics.json
```

O segundo comando só será aceito depois que o benchmark do ARBORIA for instrumentado para incluir **clusters visíveis reais** no CSV. A ausência desse campo é uma falha de evidência, não um motivo para supor zero.
