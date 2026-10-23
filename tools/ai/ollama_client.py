"""
ARBORIA ENGINE - MÓDULO DE INTEGRAÇÃO COM OLLAMA
Permite comunicação direta com instâncias locais do Ollama para geração de texto,
raciocínio botânico, geração procedural e auxílio em tempo de execução.
"""

import sys
import json
import urllib.request
import urllib.error
from typing import Dict, List, Any, Optional, Generator

DEFAULT_HOST = "http://localhost:11434"
DEFAULT_MODEL = "qwen2.5-coder:7b-floresta"

class ArboriaOllamaClient:
    def __init__(self, host: str = DEFAULT_HOST, default_model: str = DEFAULT_MODEL):
        self.host = host.rstrip("/")
        self.default_model = default_model

    def is_online(self) -> bool:
        """Verifica se o servidor Ollama está ativo e respondendo."""
        try:
            req = urllib.request.Request(f"{self.host}/api/tags", method="GET")
            with urllib.request.urlopen(req, timeout=3) as resp:
                return resp.status == 200
        except Exception:
            return False

    def list_models(self) -> List[Dict[str, Any]]:
        """Retorna a lista de todos os modelos de IA disponíveis localmente no Ollama."""
        try:
            req = urllib.request.Request(f"{self.host}/api/tags", method="GET")
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode("utf-8"))
                    return data.get("models", [])
        except Exception as e:
            print(f"[OllamaClient Error] Falha ao listar modelos: {e}", file=sys.stderr)
        return []

    def generate(
        self,
        prompt: str,
        model: Optional[str] = None,
        system: Optional[str] = None,
        temperature: float = 0.7,
        stream: bool = False
    ) -> Any:
        """
        Executa geração de texto a partir de um prompt.
        Se stream=False, retorna o texto completo (str).
        Se stream=True, retorna um gerador gerando fragmentos de texto conforme chegam.
        """
        selected_model = model or self.default_model
        payload = {
            "model": selected_model,
            "prompt": prompt,
            "stream": stream,
            "options": {
                "temperature": temperature
            }
        }
        if system:
            payload["system"] = system

        data_bytes = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{self.host}/api/generate",
            data=data_bytes,
            headers={"Content-Type": "application/json"},
            method="POST"
        )

        try:
            resp = urllib.request.urlopen(req, timeout=120)
            if not stream:
                res_data = json.loads(resp.read().decode("utf-8"))
                return res_data.get("response", "")
            else:
                def _stream_gen() -> Generator[str, None, None]:
                    for line in resp:
                        if line:
                            chunk = json.loads(line.decode("utf-8"))
                            yield chunk.get("response", "")
                return _stream_gen()
        except Exception as e:
            print(f"[OllamaClient Error] Falha na geracao: {e}", file=sys.stderr)
            return "" if not stream else iter([])

    def chat(
        self,
        messages: List[Dict[str, str]],
        model: Optional[str] = None,
        temperature: float = 0.7
    ) -> str:
        """
        Executa conversa multi-turn no formato chat:
        messages = [{'role': 'user', 'content': '...'}, {'role': 'assistant', 'content': '...'}]
        """
        selected_model = model or self.default_model
        payload = {
            "model": selected_model,
            "messages": messages,
            "stream": False,
            "options": {
                "temperature": temperature
            }
        }
        data_bytes = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{self.host}/api/chat",
            data=data_bytes,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                res_data = json.loads(resp.read().decode("utf-8"))
                msg = res_data.get("message", {})
                return msg.get("content", "")
        except Exception as e:
            print(f"[OllamaClient Error] Falha no chat: {e}", file=sys.stderr)
            return ""

    def generate_json(
        self,
        prompt: str,
        system_instruction: str = "Responda exclusivamente com um objeto JSON valido, sem markdown ou explicacoes adicionais.",
        model: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        """Gera resposta formatada e parseada em formato JSON."""
        response_text = self.generate(
            prompt=prompt,
            system=system_instruction,
            model=model,
            temperature=0.2
        )
        if not response_text:
            return None

        clean_text = response_text.strip()
        if clean_text.startswith("```json"):
            clean_text = clean_text[7:]
        if clean_text.startswith("```"):
            clean_text = clean_text[3:]
        if clean_text.endswith("```"):
            clean_text = clean_text[:-3]
        clean_text = clean_text.strip()

        try:
            return json.loads(clean_text)
        except Exception as e:
            print(f"[OllamaClient Error] Falha ao converter resposta em JSON: {e}", file=sys.stderr)
            return None


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Cliente Ollama para o ARBORIA ENGINE")
    parser.add_argument("--list", action="store_true", help="Lista as IAs disponíveis no servidor Ollama")
    parser.add_argument("--test", action="store_true", help="Testa a conexão e resposta básica")
    parser.add_argument("--prompt", type=str, help="Envia um prompt para a IA")
    parser.add_argument("--model", type=str, default=DEFAULT_MODEL, help="Nome do modelo desejado")
    args = parser.parse_args()

    client = ArboriaOllamaClient(default_model=args.model)

    print("=" * 60)
    print("  ARBORIA ENGINE — CONEXÃO OLLAMA (LOCAL AI BRIDGE)  ")
    print("=" * 60)

    if not client.is_online():
        print(f"[STATUS] Servidor Ollama Offline em {client.host}. Inicie com 'ollama serve'.")
        sys.exit(1)

    print(f"[STATUS] Servidor Ollama Online em {client.host}!")

    if args.list or (not args.test and not args.prompt):
        print("\nModelos de IA Disponíveis Localmente:")
        models = client.list_models()
        if not models:
            print("  Nenhum modelo encontrado no Ollama.")
        else:
            for m in models:
                name = m.get("name", "Desconhecido")
                size_mb = m.get("size", 0) / (1024 * 1024)
                mod_date = m.get("modified_at", "")[:10]
                tag = " [PADRAO RECOMENDADO]" if name == client.default_model else ""
                print(f"  • {name:<30} ({size_mb:>7.1f} MB) - Modificado: {mod_date}{tag}")

    if args.test:
        print(f"\n[TESTE] Enviando ping de geração para o modelo '{client.default_model}'...")
        res = client.generate("Responda em uma única frase curta: Você está pronto para auxiliar no desenvolvimento botânico e virtual geometry do Arboria Engine?", temperature=0.3)
        print(f"\n[RESPOSTA IA]:\n{res}\n")

    if args.prompt:
        print(f"\n[PROMPT ({args.model})]: {args.prompt}")
        print("-" * 60)
        res = client.generate(args.prompt, model=args.model)
        print(f"{res}\n")

if __name__ == "__main__":
    main()
