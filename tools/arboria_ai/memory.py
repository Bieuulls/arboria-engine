"""SQLite experiment memory. No training claims, just grounded retrieval."""
from __future__ import annotations
import json
import sqlite3
import time
from pathlib import Path

DDL = '''CREATE TABLE IF NOT EXISTS experiments(
 id TEXT PRIMARY KEY, created_at REAL NOT NULL, repo TEXT NOT NULL,
 target TEXT NOT NULL, model TEXT NOT NULL, goal TEXT NOT NULL,
 base_commit TEXT, before_sha TEXT NOT NULL, after_sha TEXT NOT NULL,
 status TEXT NOT NULL, reason TEXT, evidence TEXT,
 baseline_metrics TEXT, candidate_metrics TEXT);'''

class Memory:
    def __init__(self, db: Path):
        db.parent.mkdir(parents=True, exist_ok=True)
        self.con = sqlite3.connect(db)
        self.con.execute(DDL)
        self.con.commit()

    def add(self, record: dict):
        fields = ('id','repo','target','model','goal','base_commit','before_sha','after_sha','status','reason')
        vals = [record.get(x,'') for x in fields]
        self.con.execute('INSERT INTO experiments (' + ','.join(fields) + ',created_at) VALUES ('+
                         ','.join(['?']*len(fields))+',?)', vals+[time.time()])
        self.con.commit()

    def set_result(self, exp_id: str, status: str, evidence: str = '',
                   baseline: dict | None = None, candidate: dict | None = None, reason: str = ''):
        self.con.execute('UPDATE experiments SET status=?, evidence=?, baseline_metrics=?, candidate_metrics=?, reason=? WHERE id=?',
                         (status,evidence,json.dumps(baseline or {}),json.dumps(candidate or {}),reason,exp_id))
        self.con.commit()

    def recent(self, repo: str, target: str, limit: int = 6) -> list[dict]:
        cur=self.con.execute('SELECT id,status,goal,reason,baseline_metrics,candidate_metrics FROM experiments WHERE repo=? AND target=? ORDER BY created_at DESC LIMIT ?', (repo,target,limit))
        return [dict(zip(('id','status','goal','reason','baseline_metrics','candidate_metrics'),row)) for row in cur.fetchall()]

    def history(self, repo: str, limit: int = 12) -> list[dict]:
        cur=self.con.execute('SELECT id,created_at,target,model,goal,status,reason FROM experiments WHERE repo=? ORDER BY created_at DESC LIMIT ?', (repo,limit))
        return [dict(zip(('id','created_at','target','model','goal','status','reason'),row)) for row in cur.fetchall()]

    def get(self, exp_id: str) -> dict:
        cur=self.con.execute('SELECT id,repo,target,model,goal,base_commit,before_sha,after_sha,status FROM experiments WHERE id=?',(exp_id,))
        row=cur.fetchone()
        if not row: raise ValueError('Experimento não encontrado.')
        return dict(zip(('id','repo','target','model','goal','base_commit','before_sha','after_sha','status'),row))
