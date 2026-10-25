"""CLI to consult Ollama, propose bounded edits, run isolated A/B and remember results."""
from __future__ import annotations
import argparse, hashlib, json, sys, uuid
from pathlib import Path
from . import __version__
from .memory import Memory
from .ollama_client import models, propose
from .safety import apply_literal_edits, resolve_target, sha, unified_patch
from .experiment import evaluate, promote, git, assert_clean_file


def settings(repo: Path):
    config=repo/'tools'/'arboria_ai'/'config.json'
    if not config.is_file():raise ValueError('Instale o módulo na raiz do projeto. Falta tools/arboria_ai/config.json')
    return json.loads(config.read_text(encoding='utf-8'))


def state_path(repo: Path, state_opt: str):
    if state_opt:return Path(state_opt).resolve()
    key=hashlib.sha256(str(repo.resolve()).lower().encode()).hexdigest()[:12]
    return Path.home()/'.arboria_ai'/key


def cli(argv=None):
    parser=argparse.ArgumentParser(description='ARBORIA AI: sugestões Ollama com testes, evidências e memória SQLite.')
    parser.add_argument('--repo',default='.',help='Raiz do ARBORIA com .git')
    parser.add_argument('--state',default='',help='Pasta privada para experimentos (fora da árvore de código)')
    sub=parser.add_subparsers(dest='cmd',required=True)
    sub.add_parser('status',help='Verificar Ollama e modelos instalados')
    sub.add_parser('history',help='Ver histórico de experimentos')
    proposal=sub.add_parser('propose',help='Solicitar otimização pontual ao Ollama, sem alterar código')
    proposal.add_argument('--target',required=True,help='Arquivo único, relativo à raiz, como project/shaders/cull_clusters_global.glsl')
    proposal.add_argument('--goal',required=True,help='Melhoria concreta e verificável')
    proposal.add_argument('--model',default='',help='Nome exato retornado por ollama list')
    proposal.add_argument('--lines',default='',help='Faixa de contexto para arquivos grandes (ex.: 120:260)')
    cycle=sub.add_parser('cycle',help='Consultar Ollama, testar e repetir até obter candidato aprovado')
    cycle.add_argument('--target',required=True)
    cycle.add_argument('--goal',required=True)
    cycle.add_argument('--model',default='')
    cycle.add_argument('--lines',default='')
    cycle.add_argument('--attempts',type=int,default=3)
    cycle.add_argument('--promote-on-pass',action='store_true',help='Aplicar automaticamente ao working tree após testes aprovados')
    test=sub.add_parser('evaluate',help='Testar candidato em worktrees Git isoladas')
    test.add_argument('--id',required=True)
    promote_cmd=sub.add_parser('promote',help='Aplicar candidato aprovado ao working tree sem commit')
    promote_cmd.add_argument('--id',required=True)
    args=parser.parse_args(argv)
    repo=Path(args.repo).resolve(); cfg=settings(repo)
    state=state_path(repo,args.state); state.mkdir(parents=True,exist_ok=True)
    db=Memory(state/'memory.sqlite3')
    if args.cmd=='status':
        print('ARBORIA AI',__version__,'| estado:',state)
        print('Modelo configurado:',cfg['ollama'].get('model') or '(escolha via --model)')
        print('Testes configurados:',len(cfg.get('checks',[])))
        print('Benchmark configurado:',bool(cfg.get('benchmark',{}).get('argv')))
        try:
            found=models(cfg['ollama']['url'])
            print('Ollama conectado. Modelos:', ', '.join(found) or '(nenhum)')
        except Exception as e: print('Ollama indisponível:',e)
        return 0
    if args.cmd=='history':
        print(json.dumps(db.history(str(repo)),indent=2,ensure_ascii=False));return 0
    if args.cmd=='cycle':
        if not 1 <= args.attempts <= 5:raise ValueError('attempts deve ficar entre 1 e 5')
        for i in range(args.attempts):
            print(f'\n=== CICLO {i+1}/{args.attempts} ===',flush=True)
            props=['--repo',str(repo),'--state',str(state),'propose','--target',args.target,'--goal',args.goal]
            if args.model: props += ['--model',args.model]
            if args.lines: props += ['--lines',args.lines]
            rc=cli(props)
            if rc:return rc
            item=db.history(str(repo),limit=1)[0]
            exp_id=item['id']
            _=cli(['--repo',str(repo),'--state',str(state),'evaluate','--id',exp_id])
            if db.get(exp_id)['status']=='PASSED':
                if args.promote_on_pass:
                    return cli(['--repo',str(repo),'--state',str(state),'promote','--id',exp_id])
                print('CANDIDATO APROVADO. Faça review do diff e use promote --id',exp_id)
                return 0
        print('Não houve candidato aprovado; baseline mantida.')
        return 2
    if args.cmd=='propose':
        f=resolve_target(repo,args.target,cfg['target_allowlist'])
        max_size=int(cfg['limits'].get('max_source_chars',24000))
        source_bytes=f.read_bytes(); source=source_bytes.decode('utf-8')
        preview=source
        if args.lines:
            from re import fullmatch
            m=fullmatch(r'(\d+):(\d+)',args.lines)
            if not m:raise ValueError('Faixa inválida: utilize --lines 120:260')
            a,b=map(int,m.groups()); lines=source.splitlines(keepends=True)
            if a<1 or b<a or b>len(lines) or b-a>450:raise ValueError('Faixa fora dos limites.')
            preview=''.join(lines[a-1:b])
        if len(preview)>max_size:
            raise ValueError(f'Contexto contém {len(preview)} caracteres; limite {max_size}. Use --lines 120:260 para delimitar o foco.')
        try: commit=git(repo,'rev-parse','HEAD'); assert_clean_file(repo,args.target)
        except (RuntimeError,ValueError):
            raise ValueError('É obrigatório executar dentro de um repositório Git e em arquivo alvo limpo.')
        model=args.model or cfg['ollama'].get('model','')
        if not model:raise ValueError('Informe --model NOME conforme ollama list, ou configure ollama.model.')
        lessons=db.recent(str(repo),args.target)
        context='\n'.join(f"- [{r['status']}] {r['goal']}: {r['reason'] or 'sem avaliação'}" for r in lessons)[:4000]
        response=propose(cfg['ollama']['url'],model,args.target,preview,args.goal,context,
                         timeout=int(cfg['ollama'].get('timeout_seconds',240)),num_ctx=int(cfg['ollama'].get('num_ctx',8192)))
        edits=response['edits']
        after=apply_literal_edits(source,edits,args.target,
                                  max_edits=int(cfg['limits'].get('max_edits',4)),
                                  max_added_chars=int(cfg['limits'].get('max_added_chars',10000)))
        exp_id=uuid.uuid4().hex[:12]
        record={'id':exp_id,'repo':str(repo),'target':args.target,'model':model,'goal':args.goal,
                'base_commit':commit,'before_sha':sha(source_bytes),'after_sha':sha(after.encode('utf-8')),
                'edits':edits,'reason':response['reason'],'expected_benefit':response['expected_benefit'],
                'risks':response['risks']}
        folder=state/'proposals'/exp_id;folder.mkdir(parents=True,exist_ok=True)
        (folder/'proposal.json').write_text(json.dumps(record,indent=2,ensure_ascii=False),encoding='utf-8')
        (folder/'candidate.diff').write_text(unified_patch(args.target,source,after),encoding='utf-8')
        db.add({**record,'status':'PROPOSED'})
        print(json.dumps({'id':exp_id,'status':'PROPOSED','diff':str(folder/'candidate.diff'),
                          'reason':response['reason'],'risks':response['risks'],
                          'next':f'python -m tools.arboria_ai.cli --repo . evaluate --id {exp_id}'},ensure_ascii=False,indent=2))
        return 0
    path=state/'proposals'/args.id/'proposal.json'
    if not path.is_file():raise ValueError('ID desconhecido; não há proposal.json em '+str(path))
    record=json.loads(path.read_text(encoding='utf-8'))
    if record['repo']!=str(repo):raise ValueError('Proposta pertence a outro repositório.')
    if args.cmd=='evaluate':
        decision=evaluate(repo,state,cfg,record,db)
        print(json.dumps(decision,indent=2,ensure_ascii=False))
        return 0 if decision['status']=='PASSED' else 2
    if args.cmd=='promote':
        promote(repo,state,cfg,record,db)
        print('Aplicado ao working tree (SEM commit). Verifique git diff e commit manualmente.')
        return 0
    return 1


def main():
    try: sys.exit(cli())
    except Exception as ex:
        print('ERRO:',type(ex).__name__,str(ex),file=sys.stderr)
        sys.exit(2)

if __name__=='__main__':main()
