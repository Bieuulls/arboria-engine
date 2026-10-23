"""Direct Ollama API: only reads code and returns bounded structured suggestions."""
from __future__ import annotations
import json
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

EDIT_SCHEMA = {
    'type': 'object', 'properties': {
        'reason': {'type': 'string'},
        'expected_benefit': {'type': 'string'},
        'risks': {'type': 'string'},
        'edits': {'type': 'array', 'minItems': 1, 'maxItems': 4, 'items': {
            'type': 'object', 'properties': {
                'path': {'type': 'string'},
                'old_text': {'type': 'string'},
                'new_text': {'type': 'string'}},
            'required': ['path', 'old_text', 'new_text'],
            'additionalProperties': False}},
    }, 'required': ['reason', 'expected_benefit', 'risks', 'edits'],
    'additionalProperties': False,
}


def _request(url: str, data: dict | None, timeout: float):
    body = json.dumps(data).encode('utf-8') if data is not None else None
    req = Request(url, data=body, headers={'Content-Type': 'application/json'})
    try:
        with urlopen(req, timeout=timeout) as f:
            return json.loads(f.read(4_000_000).decode('utf-8'))
    except (HTTPError, URLError, TimeoutError) as ex:
        raise RuntimeError('Falha ao acessar Ollama: ' + str(ex)) from ex


def models(base: str, timeout: float = 4) -> list[str]:
    response = _request(base.rstrip('/') + '/api/tags', None, timeout)
    return [x['name'] for x in response.get('models', []) if isinstance(x, dict) and x.get('name')]


def propose(base: str, model: str, target: str, source: str, objective: str, context: str,
            timeout: int = 240, num_ctx: int = 8192) -> dict:
    system = (
        'Você é um engenheiro especialista em Vulkan, C++, GLSL e Godot. '
        'Seu trabalho é sugerir UMA otimização concreta e limitada ao arquivo mostrado. '
        'Não invente medições. Não remova geometry coverage, limites de buffers, sincronização ou verificações. '
        'Não altere testes, gates, métricas, nem código fora do arquivo alvo. '
        'Produza edições literais old_text/new_text de segmentos CURTOS, correspondentes exatamente ao texto. '
        'Não execute comandos, não produza scripts shell. Responda exclusivamente ao esquema JSON.'
    )
    user = (
        'OBJETIVO TÉCNICO: '+objective+'\nARQUIVO: '+target+'\n'
        'LIÇÕES DE EXPERIMENTOS PASSADOS:\n'+context+'\n'
        'CÓDIGO ATUAL:\n```\n'+source+'\n```\n'
        'Faça uma alteração local minimizando risco e preservando os contratos existentes.'
    )
    res = _request(base.rstrip('/') + '/api/chat', {
        'model': model,
        'stream': False,
        'format': EDIT_SCHEMA,
        'options': {'temperature': 0.15, 'num_ctx': num_ctx},
        'messages': [{'role': 'system', 'content': system}, {'role':'user','content':user}]
    }, timeout)
    content = res.get('message', {}).get('content', '')
    if not isinstance(content, str):
        raise ValueError('Ollama retornou formato inesperado.')
    from .safety import safe_json_load
    return safe_json_load(content)
