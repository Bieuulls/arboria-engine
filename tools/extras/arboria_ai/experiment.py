"""Isolated, reproducible A/B trials with fixed commands selected by engineer."""
from __future__ import annotations
import json, os, subprocess, time
from pathlib import Path
from .safety import apply_literal_edits, resolve_target, sha
from .bench import checked_metrics, aggregate, compare


def run(argv: list[str], cwd: Path, timeout: int, log: Path) -> int:
    if not isinstance(argv, list) or not argv or not all(isinstance(x,str) and x for x in argv):
        raise ValueError('Comando deve ser lista JSON de argumentos de executável.')
    log.parent.mkdir(parents=True,exist_ok=True)
    begin=time.perf_counter()
    try:
        cp=subprocess.run(argv, cwd=str(cwd), capture_output=True, text=True, errors='replace', timeout=timeout,
                          shell=False, env=os.environ.copy())
        status=cp.returncode
        output='CMD: '+json.dumps(argv,ensure_ascii=False)+'\nEXIT: '+str(status)+'\nSECONDS: '+str(round(time.perf_counter()-begin,3))+'\nSTDOUT:\n'+cp.stdout[-100000:]+'\nSTDERR:\n'+cp.stderr[-100000:]
    except subprocess.TimeoutExpired as ex:
        status=124
        output=f'CMD: {argv!r}\nTIMEOUT after {timeout}s: {ex}\n'
    except FileNotFoundError as ex:
        status=127
        output='EXECUTABLE NOT FOUND: '+str(ex)
    log.write_text(output,encoding='utf-8')
    return status


def git(repo: Path, *args: str) -> str:
    result=subprocess.run(['git','-C',str(repo),*args],capture_output=True,text=True,errors='replace')
    if result.returncode:raise RuntimeError(f'Git {args}: {result.stderr.strip()}')
    return result.stdout.strip()


def git_root(repo: Path) -> Path:
    root=Path(git(repo,'rev-parse','--show-toplevel')).resolve()
    if repo.resolve()!=root: raise ValueError('Use a raiz do repositório Git.')
    return root


def assert_clean_file(repo: Path, target: str):
    # Only target needs clean and tracked; unrelated work may exist and must not be touched.
    try: git(repo, 'ls-files','--error-unmatch','--',target)
    except RuntimeError as ex:raise ValueError('Arquivo alvo não está versionado pelo Git.') from ex
    if git(repo,'status','--porcelain','--',target):
        raise ValueError('Arquivo alvo possui modificações locais. Preserve-as antes de otimizar.')


def _checkout(repo: Path, worktree: Path, commit: str):
    if worktree.exists():raise FileExistsError('Worktree já existe: '+str(worktree))
    worktree.parent.mkdir(parents=True,exist_ok=True)
    git(repo,'worktree','add','--detach',str(worktree),commit)


def _checks(cfg: dict, root: Path, report_dir: Path, label: str):
    checks=cfg.get('checks',[])
    if not checks:
        raise ValueError('NENHUM TESTE CONFIGURADO: a avaliação reprova por segurança. Edite config.json.')
    for n,check in enumerate(checks):
        if not isinstance(check,dict) or not check.get('argv'):
            raise ValueError('Check sem comando explícito: '+str(check))
        rc=run(check['argv'],root,int(check.get('timeout_seconds',900)), report_dir/f'{label}_check_{n:02d}.log')
        if rc:raise RuntimeError(f'{label}: {check.get("name",n)} falhou (exit {rc}).')


def _one_bench(cfg: dict, root: Path, report_dir: Path, label: str, idx: int) -> dict:
    bench=cfg.get('benchmark',{})
    if not bench.get('argv') or not bench.get('output_json'):
        raise ValueError('Benchmark JSON real não configurado: configure benchmark.argv e output_json.')
    relative=Path(bench['output_json'])
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Arquivo de métricas fora da worktree.')
    out=(root/relative).resolve()
    if not out.is_relative_to(root.resolve()):raise ValueError('Métrica fora da worktree.')
    out.parent.mkdir(parents=True,exist_ok=True)
    out.unlink(missing_ok=True)  # prevents stale benchmarks from approving candidates
    rc=run(bench['argv'],root,int(bench.get('timeout_seconds',3600)),report_dir/f'{label}_benchmark_{idx:02d}.log')
    if rc:raise RuntimeError(f'Benchmark {label} execução {idx} retornou {rc}.')
    m=checked_metrics(out)
    (report_dir/f'{label}_metrics_{idx:02d}.json').write_text(json.dumps(m,indent=2),encoding='utf-8')
    return m


def evaluate(repo: Path, state: Path, cfg: dict, proposal: dict, memory) -> dict:
    repo=git_root(repo)
    if not cfg.get('checks') or not cfg.get('benchmark', {}).get('argv') or not cfg.get('benchmark', {}).get('output_json'):
        raise ValueError('Avaliação bloqueada: configure checks e benchmark real antes de abrir worktrees.')
    target=proposal['target']; commit=proposal['base_commit']; exp_id=proposal['id']
    assert_clean_file(repo,target)
    if git(repo,'rev-parse','HEAD') != commit:
        raise ValueError('O commit mudou desde a proposta. Gere nova proposta sobre a versão atual.')
    f=resolve_target(repo,target,cfg['target_allowlist'])
    source=f.read_bytes()
    if sha(source)!=proposal['before_sha']:
        raise ValueError('Arquivo alterado desde a proposta.')
    before=source.decode('utf-8')
    after=apply_literal_edits(before,proposal['edits'],target,
                              max_edits=int(cfg['limits'].get('max_edits',4)),
                              max_added_chars=int(cfg['limits'].get('max_added_chars',10000)))
    if sha(after.encode('utf-8'))!=proposal['after_sha']:
        raise ValueError('Proposta armazenada não coincide com seu hash.')
    directory=state/'experiments'/exp_id
    original=directory/'baseline'
    candidate=directory/'candidate'
    report=directory/'evidence'; report.mkdir(parents=True,exist_ok=True)
    result={'id':exp_id,'status':'REJECTED','baseline':{},'candidate':{},'reason':''}
    try:
        _checkout(repo,original,commit)
        _checkout(repo,candidate,commit)
        target_file=resolve_target(candidate,target,cfg['target_allowlist'])
        target_file.write_bytes(after.encode('utf-8'))
        _checks(cfg,original,report,'baseline')
        _checks(cfg,candidate,report,'candidate')
        n=int(cfg.get('benchmark',{}).get('repetitions',3))
        if n < 3 or n > 15:raise ValueError('Benchmark exige de 3 a 15 repetições por versão.')
        base_runs=[]; cand_runs=[]
        for i in range(n):
            # Interleave A/B to limit thermal and clock drift bias.
            base_runs.append(_one_bench(cfg,original,report,'baseline',i))
            cand_runs.append(_one_bench(cfg,candidate,report,'candidate',i))
        base=aggregate(base_runs); cand=aggregate(cand_runs)
        approved, notes=compare(base,cand,cfg.get('acceptance',{}))
        result.update({'status':'PASSED' if approved else 'REJECTED',
                       'baseline':base,'candidate':cand,'reason':' | '.join(notes)})
    except Exception as e:
        result['reason']=type(e).__name__+': '+str(e)
    # Preserve worktrees on failure as debugging evidence; never write to main tree.
    (report/'decision.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
    memory.set_result(exp_id,result['status'],str(report/'decision.json'),result['baseline'],result['candidate'],result['reason'])
    return result


def promote(repo: Path, state: Path, cfg: dict, proposal: dict, memory) -> None:
    repo=git_root(repo)
    exp_id=proposal['id']; target=proposal['target']
    rec=memory.get(exp_id)
    if rec['status'] != 'PASSED':raise ValueError('Apenas experimentos que passaram por todos os checks podem ser promovidos.')
    assert_clean_file(repo,target)
    if git(repo,'rev-parse','HEAD') != proposal['base_commit']:
        raise ValueError('Branch divergiu desde o experimento; reavalie.')
    f=resolve_target(repo,target,cfg['target_allowlist'])
    if sha(f.read_bytes()) != proposal['before_sha']:raise ValueError('Arquivo modificado.')
    after=apply_literal_edits(f.read_bytes().decode('utf-8'),proposal['edits'],target,
                              max_edits=int(cfg['limits'].get('max_edits',4)),
                              max_added_chars=int(cfg['limits'].get('max_added_chars',10000)))
    if sha(after.encode('utf-8')) != proposal['after_sha']:raise ValueError('Hash divergente.')
    f.write_bytes(after.encode('utf-8'))
    # Do not commit automatically: Antigravity reviews the diff and records the evidence.
