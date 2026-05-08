class_name CustomerQueue
extends RefCounted

signal active_promoted
signal order_shown(order_id: StringName)
signal active_customer_left
signal queue_customer_left

enum State { QUEUE, APPROACHING, ANNOUNCING, SERVING }

class Customer extends RefCounted:
	var order_ids: Array[StringName] = [] # для VIP: 2-3, для обычного: 1
	var state: int = State.QUEUE
	var state_time: float = 0.0

	var archetype: int = HeroArchetypes.Type.NORMAL
	var is_vip: bool = false

	var queue_patience_max: float = 10.0
	var queue_patience: float = 10.0

	var serve_patience_max: float = 12.0
	var serve_patience: float = 12.0
	var serve_time: float = 0.0


var queue_size: int = 3
var approach_time: float = 0.7
var announce_time: float = 0.4
var queue_drain_mult: float = 0.25

var _make_order_ids: Callable     # (count:int) -> Array[StringName]
var _pick_archetype: Callable     # () -> int
var _serve_patience_max_fn: Callable # () -> float

var _active: Customer = null
var _queue: Array[Customer] = []

var _vip_pending_count: int = 0


func setup(make_order_ids_fn: Callable, pick_archetype_fn: Callable, serve_patience_max_fn: Callable,
		vip_order_count: int = 0,
		p_queue_size: int = 3, p_approach_time: float = 0.7, p_announce_time: float = 0.4, p_queue_drain_mult: float = 0.25) -> void:
	_make_order_ids = make_order_ids_fn
	_pick_archetype = pick_archetype_fn
	_serve_patience_max_fn = serve_patience_max_fn
	_vip_pending_count = vip_order_count

	queue_size = p_queue_size
	approach_time = p_approach_time
	announce_time = p_announce_time
	queue_drain_mult = p_queue_drain_mult

	_active = null
	_queue.clear()

	# VIP кладём первым в очередь, если есть
	if _vip_pending_count > 0:
		_queue.append(_spawn_vip_customer(_vip_pending_count))
		_vip_pending_count = 0

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
	_active = null
	_promote_next_customer()


# ---------- internals ----------

func _spawn_normal_customer() -> Customer:
	var c := Customer.new()
	var raw = _make_order_ids.call(1)
	c.order_ids = []
	if raw is Array:
		for x in raw:
			c.order_ids.append(StringName(x))
	if c.order_ids.is_empty():
		c.order_ids.append(StringName())
	c.archetype = int(_pick_archetype.call())
	c.is_vip = false
	c.queue_patience = c.queue_patience_max
	c.state = State.QUEUE
	return c


func _spawn_vip_customer(count: int) -> Customer:
	var c := Customer.new()
	var raw = _make_order_ids.call(1)
	c.order_ids = []
	if raw is Array:
		for x in raw:
			c.order_ids.append(StringName(x))
	if c.order_ids.is_empty():
		c.order_ids.append(StringName())
	c.archetype = HeroArchetypes.Type.NORMAL
	c.is_vip = true
	c.queue_patience = c.queue_patience_max * 1.5 # VIP чуть терпеливее в очереди
	c.queue_patience_max = c.queue_patience
	c.state = State.QUEUE
	return c


func _fill_queue() -> void:
	while _queue.size() < queue_size:
		_queue.append(_spawn_normal_customer())


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
				if _active.is_vip:
					mult *= 1.25 # VIP чуть терпеливее в обслуживании

				_active.serve_patience_max = base_pat * mult
				_active.serve_patience = _active.serve_patience_max
				_active.serve_time = 0.0

				# сигнал оставим прежним, но Shop будет читать active.order_ids
				var first_id := _active.order_ids[0] if not _active.order_ids.is_empty() else StringName()
				order_shown.emit(first_id)

		State.SERVING:
			_active.serve_patience -= delta
			_active.serve_time += delta
			if _active.serve_patience <= 0.0:
				_active = null
				active_customer_left.emit()
				_promote_next_customer()
