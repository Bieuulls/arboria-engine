# ARBORIA ENGINE — INTEGRACAO CONTINUA LOCAL (CI LOCAL)
$ErrorActionPreference = "Stop"

Write-Host "==============================================================================="
Write-Host " ARBORIA ENGINE - INTEGRACAO CONTINUA LOCAL (CI LOCAL)"
Write-Host "==============================================================================="

Write-Host "`n[CI 1/5] Compilando Backend C++ Nativo (native/renderer/build)..."
& cmake --build native/renderer/build --config Release
if ($LASTEXITCODE -ne 0) {
    Write-Error "[FALHA] Falha na compilacao do modulo C++ nativo!"
    exit 1
}
Write-Host "[OK] Compilacao C++ concluida com sucesso."

Write-Host "`n[CI 2/5] Executando Testes Unitarios C++ (CTest)..."
& ctest --test-dir native/renderer/build --output-on-failure
if ($LASTEXITCODE -ne 0) {
    Write-Error "[FALHA] Testes unitarios C++ falharam!"
    exit 1
}
Write-Host "[OK] 100% dos testes unitarios C++ aprovados."

Write-Host "`n[CI 3/5] Executando Suite do Painel de Testes (tests/panel/panel.py)..."
& python tests/panel/panel.py --cli
if ($LASTEXITCODE -ne 0) {
    Write-Error "[FALHA] Suite do painel de testes falhou!"
    exit 1
}
Write-Host "[OK] Painel de testes executado com 100% de aprovacao."

Write-Host "`n[CI 4/5] Executando Benchmark Rapido (dense_rock: 1 e 500 instancias)..."
& python bench/runner.py --scenario dense_rock --instances 1,500 --warmup 10 --measured 30
if ($LASTEXITCODE -ne 0) {
    Write-Error "[FALHA] Execucao do benchmark rapido falhou!"
    exit 1
}
Write-Host "[OK] Benchmark rapido concluido com telemetria gravada."

Write-Host "`n[CI 5/5] Verificando Neutralizacao de Caminhos Locais no Repositorio..."
& python tests/test_path_neutralization.py
if ($LASTEXITCODE -ne 0) {
    Write-Error "[FALHA] Caminhos locais detectados no repositorio!"
    exit 1
}
Write-Host "[OK] 0 caminhos locais detectados no repositorio."

Write-Host "`n==============================================================================="
Write-Host " RESULTADO FINAL DA CI LOCAL: [PASSOU] - TODAS AS ETAPAS FORAM APROVADAS"
Write-Host "==============================================================================="
exit 0
