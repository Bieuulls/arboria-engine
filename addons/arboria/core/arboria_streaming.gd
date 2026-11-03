# ARBORIA ENGINE — Módulo de Streaming VRAM (GDScript)
# Fase 3 da Modularização: Gerenciamento de páginas de geometria, orçamento VRAM,
# eviction LRU e page fault fallback.
# Extraído de arboria_native_pipeline.gd.

extends RefCounted
class_name ArboriaStreaming

# Referência ao pipeline nativo
var native_pipeline: ArboriaNativePipeline = null

# Orçamento VRAM em bytes
var vram_budget: uint = 0
var vram_used: uint = 0
var vram_resident: uint = 0

# Páginas registradas (page_id -> dados da página)
var pages: Dictionary = {}

# Ordem LRU (page_id mais antigo primeiro)
var lru_order: Array = []

# Página raiz sempre residente
var root_page_id: uint = 0

# Estatísticas
var stats: StreamingStats = StreamingStats.new()

func _init(pipeline: ArboriaNativePipeline = null):
	native_pipeline = pipeline
	stats.vram_budget_bytes = vram_budget

func set_pipeline(pipeline: ArboriaNativePipeline):
	native_pipeline = pipeline

func set_vram_budget(bytes: uint):
	vram_budget = bytes
	stats.vram_budget_bytes = bytes
	_check_budget()

# --- Registro de Página ---

func register_page(page_id: uint, size_bytes: uint, is_root: bool = false):
	var page_data: Dictionary = {
		"id": page_id,
		"size": size_bytes,
		"resident": false,
		"last_access": Time.get_ticks_msec(),
		"is_root": is_root
	}
	pages[page_id] = page_data
	if is_root:
		root_page_id = page_id
		make_page_resident(page_id)

# Tornar uma página residente na VRAM
func make_page_resident(page_id: uint) -> bool:
	if not pages.has(page_id):
		return false
	var page: Dictionary = pages[page_id]
	if page.resident:
		return true
	# Verifica orçamento
	if vram_resident + page.size > vram_budget and not page.is_root:
		_evict_lru(page.size)
	page.resident = true
	vram_resident += page.size
	page.last_access = Time.get_ticks_msec()
	if page_id in lru_order:
		lru_order.erase(page_id)
	stats.resident_pages += 1
	stats.vram_resident_bytes = vram_resident
	return true

# Evictar página LRU para fazer espaço
func _evict_lru(needed_bytes: uint):
	while vram_resident + needed_bytes > vram_budget and lru_order.size() > 0:
		var page_id: uint = lru_order.pop_front()
		var page: Dictionary = pages[page_id]
		if page and not page.is_root and page.resident:
			page.resident = false
			vram_resident -= page.size
			stats.evicted_pages += 1
	stats.vram_resident_bytes = vram_resident

# Verificar orçamento VRAM
func _check_budget():
	if vram_resident > vram_budget:
		_evict_lru(0)

# --- Page Fault ---

func handle_page_fault(page_id: uint) -> bool:
	stats.page_faults += 1
	return make_page_resident(page_id)

# Atualização de streaming por frame (chamado a cada frame com posição da câmera)
func update(cam_pos: Vector3, current_frame: uint):
	# Determinar páginas necessárias baseado na posição da câmera
	# Fazer páginas necessárias residentes
	# Evictar páginas não necessárias (LRU)
	pass

func get_stats() -> StreamingStats:
	return stats
