extends SceneTree

## One symbol advancing a frame must not rebuild every other symbol sharing
## its atlas.
##
## gdanimate kept use_backbuffer_cache and backbuffer_cache on the AnimateAtlas
## resource. An atlas is one resource per atlas folder and every AnimateSymbol
## naming it holds the same one, so both fields were shared mutable state:
## _draw_impl set the flag false whenever *a* symbol's frame advanced, and the
## next symbol to draw then found it false and took the full rebuild path -
## freeing and recreating every canvas item RID it owns - with nothing of its
## own having changed.
##
## Monochrome's device log is where this costs: anim2d 371ms/s in that system
## with rebuild 95-100% of it, 480 rebuilds in one second against 1665 cached
## draws, single rebuilds at 14.04ms and 37.63ms.
##
## The cache being shared was the worse half and is not about speed at all: it
## holds the RIDs of whichever symbol rebuilt last, so a symbol on the cheap
## path was moving another symbol's backbuffer copy rects to its own transform.
##
## Run with:
##   godot --headless --path . --script tools/test_atlas_cache_per_symbol.gd

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	# A bare AdobeAtlas with no stage symbol: draw_on() returns immediately,
	# so nothing is rendered and the only thing exercised is the decision -
	# which is the whole of what this is about. Parsing a real atlas would
	# need textures a headless run cannot import.
	var atlas := AdobeAtlas.new()

	var a := AnimateSymbol.new()
	var b := AnimateSymbol.new()
	for symbol in [a, b]:
		symbol.atlases = _atlases(atlas)
		root.add_child(symbol)
		# Both have moved, so both are entitled to the cheap path.
		symbol._use_backbuffer_cache = true

	_check("los dos comparten el mismo atlas",
		a.get_atlas() == b.get_atlas())
	_check("pero no la misma cache",
		not is_same(a._backbuffer_cache, b._backbuffer_cache))

	# A's frame advances; B's does not.
	a.frame_dirty = true

	var before: Dictionary = AnimateSymbol.take_draw_stats()
	a._draw()
	var after_a: Dictionary = AnimateSymbol.take_draw_stats()
	b._draw()
	var after_b: Dictionary = AnimateSymbol.take_draw_stats()

	_check("el que avanza de frame reconstruye",
		int(after_a.get(&"rebuilds", 0)) == 1,
		"rebuilds=%s cached=%s" % [after_a.get(&"rebuilds"), after_a.get(&"cached")])

	_check("el otro no",
		int(after_b.get(&"rebuilds", 0)) == 0 and int(after_b.get(&"cached", 0)) == 1,
		"rebuilds=%s cached=%s" % [after_b.get(&"rebuilds"), after_b.get(&"cached")])

	# And the flag it consumed is its own: A cleared its own on the rebuild,
	# B still has one.
	_check("A gasta su propio permiso", not a._use_backbuffer_cache)
	_check("y no toca el de B", b._use_backbuffer_cache)

	# The atlas must not be carrying either field any more - a leftover would
	# be read by nothing and quietly re-share the state on the next edit.
	_check("el atlas ya no lleva use_backbuffer_cache",
		not (&"use_backbuffer_cache" in atlas))

	_check("stats se leen y se reinician", int(before.get(&"rebuilds", -1)) >= 0)

	a.queue_free()
	b.queue_free()

	print("")
	if _checks < 8:
		print("FALLO: solo %d de 8 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - la cache del atlas es de cada simbolo")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _atlases(atlas: AnimateAtlas) -> Array[AnimateAtlas]:
	var typed: Array[AnimateAtlas] = []
	typed.append(atlas)
	return typed

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-46s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-46s%s" % [label, "  (%s)" % detail if detail else ""])
