@echo off
setlocal

echo ===============================================================================
echo  ARBORIA ENGINE - INTEGRACAO CONTINUA LOCAL (CI LOCAL)
echo ===============================================================================

echo [CI 1/5] Compilando Backend C++ Nativo (native/renderer/build)...
cmake --build native/renderer/build --config Release
if errorlevel 1 (
    echo [FALHA] Falha na compilacao do modulo C++ nativo!
    exit /b 1
)
echo [OK] Compilacao C++ concluida com sucesso.
echo.

echo [CI 2/5] Executando Testes Unitarios C++ (CTest)...
ctest --test-dir native/renderer/build --output-on-failure
if errorlevel 1 (
    echo [FALHA] Testes unitarios C++ falharam!
    exit /b 1
)
echo [OK] 100%% dos testes unitarios C++ aprovados.
echo.

echo [CI 3/5] Executando Suite do Painel de Testes (tests/panel/panel.py)...
python tests/panel/panel.py --cli
if errorlevel 1 (
    echo [FALHA] Suite do painel de testes falhou!
    exit /b 1
)
echo [OK] Painel de testes executado com 100%% de aprovacao.
echo.

echo [CI 4/5] Executando Benchmark Rapido (dense_rock: 1 e 500 instancias)...
python bench/runner.py --scenario dense_rock --instances 1,500 --warmup 10 --measured 30
if errorlevel 1 (
    echo [FALHA] Execucao do benchmark rapido falhou!
    exit /b 1
)
echo [OK] Benchmark rapido concluido com telemetria gravada.
echo.

echo [CI 5/5] Verificando Neutralizacao de Caminhos Locais no Repositorio...
python tests/test_path_neutralization.py
if errorlevel 1 (
    echo [FALHA] Caminhos locais detectados no repositorio!
    exit /b 1
)
echo [OK] 0 caminhos locais detectados no repositorio.
echo.

echo ===============================================================================
echo  RESULTADO FINAL DA CI LOCAL: [PASSOU] - TODAS AS ETAPAS FORAM APROVADAS
echo ===============================================================================
exit /b 0
