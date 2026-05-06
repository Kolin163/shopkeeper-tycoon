class_name CustomerQueue
extends RefCounted

signal active_promoted
signal order_shown(order_id: StringName)
signal active_customer_left
signal queue_customer_left

enum State { QUEUE, APPROACHING, ANNOUNCING, SERVING }

class Customer extends RefCounted:
	var archetype: int = HeroArchetypes.Type.NORMAL
	var order_id: StringName = StringName()
	var state: int = State.QUEUE
	var state_time: float = 0.0

	var queue_patience_max: float = 10.0
	var queue_patience: float = 10.0

	var serve_patience_max: float = 12.0
	var serve_patience: float = 12.0
	var serve_time: float = 0.0


var queue_size: int = 3
var approach_time: float = 0.7
var announce_time: float = 0.4
var queue_drain_mult: float = 0.25

var _pick_order_id: Callable
var _pick_archetype: Callable
var _serve_patience_max_fn: Callable

var _active: Customer = null
var _queue: Array[Customer] = []


func setup(pick_order_id_fn: Callable, pick_archetype_fn: Callable, serve_patience_max_fn: Callable,
		p_queue_size: int = 3, p_approach_time: float = 0.7, p_announce_time: float = 0.4, p_queue_drain_mult: float = 0.25) -> void:
	_pick_order_id = pick_order_id_fn
	_pick_archetype = pick_archetype_fn
	_serve_patience_max_fn = serve_patience_max_fn

	queue_size = p_queue_size
	approach_time = p_approach_time
	announce_time = p_announce_time
	queue_drain_mult = p_queue_drain_mult

	_active = null
	_queue.clear()
	_fill_queue()
	_promote_next_customer()


func update(delta: float) -> void:
	_update_queue(delta)
	_update_active(delta)


func get_active() -> Customer:
	return _active


func get_queue() -> Array[Customer]:
	return _queue


func is_order_visible() -> bool:
	return _active != null and _active.state == State.SERVING


func complete_active_order() -> void:
	# Вызывается из Shop, когда предмет доставлен.
	_active = null
	_promote_next_customer()


# ---------- internals ----------

func _spawn_customer() -> Customer:
	var c := Customer.new()
	c.order_id = _pick_order_id.call() as StringName
	c.archetype = int(_pick_archetype.call())
	c.queue_patience = c.queue_patience_max
	c.state = State.QUEUE
	return c


func _fill_queue() -> void:
	while _queue.size() < queue_size:
		_queue.append(_spawn_customer())


func _promote_next_customer() -> void:
	if _active != null:
		return

	if _queue.is_empty():
		_fill_queue()

	_active = _queue.pop_front()
	_active.state = State.APPROACHING
	_active.state_time = approach_time
	active_promoted.emit()

	_fill_queue()


func _update_queue(delta: float) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		var c := _queue[i]
		c.queue_patience -= delta * queue_drain_mult
		if c.queue_patience <= 0.0:
			_queue.remove_at(i)
			queue_customer_left.emit()

	_fill_queue()


func _update_active(delta: float) -> void:
	if _active == null:
		_promote_next_customer()
		return

	match _active.state:
		State.APPROACHING:
			_active.state_time -= delta
			if _active.state_time <= 0.0:
				_active.state = State.ANNOUNCING
				_active.state_time = announce_time

		State.ANNOUNCING:
			_active.state_time -= delta
			if _active.state_time <= 0.0:
				_active.state = State.SERVING
				var base_pat := float(_serve_patience_max_fn.call())
				var mult := HeroArchetypes.patience_mult(_active.archetype)
				_active.serve_patience_max = base_pat * mult
				_active.serve_patience = _active.serve_patience_max
				_active.serve_time = 0.0
				order_shown.emit(_active.order_id)

		State.SERVING:
			_active.serve_patience -= delta
			_active.serve_time += delta
			if _active.serve_patience <= 0.0:
				_active = null
				active_customer_left.emit()
				_promote_next_customer()
