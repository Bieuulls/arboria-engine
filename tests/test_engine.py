import json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.arboria_ai.safety import normalize_target, apply_literal_edits, sha
from tools.arboria_ai.bench import checked_metrics, compare, aggregate
from tools.arboria_ai.memory import Memory
from tools.arboria_ai.experiment import evaluate, promote

ALLOW=['project/shaders/*.glsl','native/renderer/**/*.cpp']

class TestSafety(unittest.TestCase):
    def test_paths(self):
        self.assertEqual(normalize_target('project/shaders/a.glsl',ALLOW),'project/shaders/a.glsl')
        for x in ('../secret.glsl','tools/gates/x.cpp','/tmp/a.cpp','project/../a.glsl',r'..\secret.cpp','project/shaders/test.gd'):
            with self.subTest(x=x),self.assertRaises(ValueError):normalize_target(x,ALLOW)

    def test_literal_edits(self):
        src='hello gpu\nmesh id: 1\n'
        self.assertEqual(apply_literal_edits(src,[{'path':'a.glsl','old_text':'mesh id: 1','new_text':'mesh id: 2'}],'a.glsl'), 'hello gpu\nmesh id: 2\n')
        with self.assertRaises(ValueError):apply_literal_edits(src,[{'path':'other.glsl','old_text':'hello','new_text':'oops'}],'a.glsl')
        with self.assertRaises(ValueError):apply_literal_edits('aaa', [{'path':'a','old_text':'a','new_text':'b'}],'a')

    def test_zero_geometry_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'metrics.json'
            p.write_text(json.dumps({'gpu_p95_ms':1,'frame_p95_ms':2,'vram_mb':20,'visible_clusters':0,'visual_error':0}))
            with self.assertRaisesRegex(ValueError,'zero clusters'):checked_metrics(p)

    def test_stale_metrics_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError,'não gerou'):checked_metrics(Path(tmp)/'missing.json')

    def test_compare(self):
        a={'gpu_p95_ms':10.,'frame_p95_ms':11.,'vram_mb':120.,'visible_clusters':500.,'visual_error':0.0}
        b={**a,'gpu_p95_ms':9.0}
        self.assertTrue(compare(a,b,{})[0])
        self.assertFalse(compare(a,{**b,'frame_p95_ms':13},{})[0])
        self.assertTrue(compare(a,{**b,'visible_clusters':400},{})[0],"Culling pode reduzir clusters se a imagem permanece válida")
        self.assertFalse(compare(a,{**b,'visible_clusters':400},{'require_cluster_count_parity':True})[0])
        self.assertFalse(compare(a,{**b,'visual_error':0.1},{})[0])
        self.assertFalse(compare(a,{**a,'gpu_p95_ms':10.1},{})[0])

    def test_memory(self):
        with tempfile.TemporaryDirectory() as d:
            m=Memory(Path(d)/'mem.sqlite3')
            m.add({'id':'ex1','repo':'R','target':'p.glsl','model':'local','goal':'opt','base_commit':'c','before_sha':'b','after_sha':'a','status':'PROPOSED'})
            self.assertEqual(m.get('ex1')['status'],'PROPOSED')
            m.set_result('ex1','REJECTED',reason='no GPU')
            self.assertEqual(m.recent('R','p.glsl')[0]['reason'],'no GPU')
            m.con.close()

    def test_gate_fail_closed(self):
        with tempfile.TemporaryDirectory() as d:
            from tools.arboria_ai.experiment import _checks
            with self.assertRaisesRegex(ValueError,'NENHUM TESTE'):_checks({'checks':[]},Path(d),Path(d),'baseline')

    def test_git_worktree_real_a_b_runner(self):
        # Real git, real file edits and real subprocesses. Synthetic fixture metrics
        # verify the orchestration only; NOT a GPU benchmark.
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);repo=root/'repo';repo.mkdir()
            (repo/'project/shaders').mkdir(parents=True)
            target='project/shaders/cull.glsl';f=repo/target
            f.write_bytes(b'ORIGINAL\n')
            (repo/'checks.py').write_bytes(b'from pathlib import Path\np=Path("project/shaders/cull.glsl")\nassert p.read_text().strip() in ("ORIGINAL","BETTER")\n')
            (repo/'bench.py').write_bytes(b'import json\nfrom pathlib import Path\ngood="BETTER" in Path("project/shaders/cull.glsl").read_text()\np=Path("artifacts/aeoc_metrics.json")\np.parent.mkdir(parents=True,exist_ok=True)\np.write_text(json.dumps({"gpu_p95_ms":9 if good else 10,"frame_p95_ms":10 if good else 11,"vram_mb":101,"visible_clusters":100,"visual_error":0}))\n')
            def g(*args):
                p=subprocess.run(['git','-C',str(repo),*args],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                self.assertEqual(p.returncode,0,p.stderr)
                return p.stdout.strip()
            g('init','-q');g('config','user.name','Tests');g('config','user.email','test@example.org');g('config','core.autocrlf','false');g('add','.');g('commit','-qm','baseline')
            commit=g('rev-parse','HEAD')
            cfg={'target_allowlist':ALLOW,'limits':{'max_edits':4,'max_added_chars':10000},
                 'checks':[{'name':'sanity','argv':[sys.executable,'checks.py'],'timeout_seconds':10}],
                 'benchmark':{'argv':[sys.executable,'bench.py'],'output_json':'artifacts/aeoc_metrics.json','repetitions':3,'timeout_seconds':15},
                 'acceptance':{}}
            state=root/'state';db=Memory(state/'db.sqlite3')
            try:
                source=f.read_bytes();after=b'BETTER\n'
                prop={'id':'abc123','repo':str(repo.resolve()),'target':target,'model':'test','goal':'save GPU','base_commit':commit,
                      'before_sha':sha(source),'after_sha':sha(after),'edits':[{'path':target,'old_text':'ORIGINAL','new_text':'BETTER'}]}
                db.add({**prop,'status':'PROPOSED'})
                result=evaluate(repo,state,cfg,prop,db)
                self.assertEqual(result['status'],'PASSED',result)
                self.assertEqual(f.read_bytes(),source,'Candidate must not alter working tree before promote')
                promote(repo,state,cfg,prop,db)
                self.assertEqual(f.read_bytes(),after)
                self.assertTrue((state/'experiments/abc123/evidence/decision.json').exists())
            finally:
                db.con.close()

if __name__=='__main__':unittest.main()

class TestOllamaTransport(unittest.TestCase):
    def test_models_and_schema_response_via_http(self):
        """Protocol/transport test with local HTTP fixture; not an actual Ollama run."""
        from http.server import BaseHTTPRequestHandler, HTTPServer
        from threading import Thread
        from tools.arboria_ai.ollama_client import models, propose, EDIT_SCHEMA
        got=[]
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_GET(self):
                self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers()
                self.wfile.write(json.dumps({'models':[{'name':'qwen-coder-local:test'}]}).encode())
            def do_POST(self):
                obj=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                got.append(obj)
                ans={'message':{'content':json.dumps({'reason':'measurable optimization','expected_benefit':'less search','risks':'off-by-one','edits':[{'path':'project/shaders/cull.glsl','old_text':'linear();','new_text':'prefix();'}]})}}
                self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers()
                self.wfile.write(json.dumps(ans).encode())
        srv=HTTPServer(('127.0.0.1',0),Handler)
        t=Thread(target=srv.serve_forever,daemon=True);t.start()
        try:
            base='http://127.0.0.1:'+str(srv.server_port)
            self.assertEqual(models(base),['qwen-coder-local:test'])
            p=propose(base,'qwen-coder-local:test','project/shaders/cull.glsl','void main(){ linear(); }','reduce search cost','none')
            self.assertEqual(p['edits'][0]['new_text'],'prefix();')
            self.assertEqual(got[0]['stream'],False)
            self.assertEqual(got[0]['format']['type'],'object')
            self.assertEqual(got[0]['model'],'qwen-coder-local:test')
        finally: srv.shutdown();srv.server_close();t.join(timeout=3)

class TestVisualComparison(unittest.TestCase):
    def test_real_png_mae(self):
        from PIL import Image
        from tools.arboria_ai.visual_compare import compare_png
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            a=root/'a.png';b=root/'b.png'
            Image.new('RGB',(12,12),(100,100,100)).save(a)
            Image.new('RGB',(12,12),(100,100,100)).save(b)
            self.assertEqual(compare_png(a,b)['visual_error'],0.0)
            Image.new('RGB',(12,12),(0,0,0)).save(b)
            self.assertGreater(compare_png(a,b)['visual_error'],0.3)
