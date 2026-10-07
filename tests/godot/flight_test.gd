extends SceneTree

var failures := 0
var result: Dictionary = {}
var drone: MARCDrone
var arena: MARCArena
var competition := MARCCompetition.new()

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, name: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + name)

func run_command(op: String, args := {}) -> bool:
	result.clear()
	drone.accept_command({"id":"test","op":op,"args":args,"timeout":25})
	var frames := 0
	while result.is_empty() and frames < 4000:
		await physics_frame
		frames += 1
	print("FLIGHT ",op," ",JSON.stringify(result)," pose=",JSON.stringify(drone.pose()))
	return bool(result.get("ok",false))

func run() -> void:
	arena = MARCArena.new()
	root.add_child(arena)
	drone = MARCDrone.new()
	drone.arena = arena
	drone.profile = JSON.parse_string(FileAccess.get_file_as_string("res://config/profiles/stable.json"))
	root.add_child(drone)
	drone.manual_enabled = false
	drone.command_completed.connect(func(_id: String, ok: bool, message: String): result = {"ok":ok,"message":message})
	competition.prepare()
	competition.begin()
	for _i in 60: await physics_frame
	expect(await run_command("takeoff",{"h":50}),"physical takeoff")
	expect(drone.global_position.y > 0.55,"real lift")
	expect(await run_command("goto",{"x":100,"y":200,"h":90}),"approach shortcut")
	expect(await run_command("goto",{"x":180,"y":200,"h":90}),"pass shortcut")
	expect(competition.counts.get("6",0) == 1,"physical shortcut judged")
	expect(await run_command("turn",{"degrees":360}),"full 360-degree physical turn")
	expect(absf(drone.turn_accumulated - 360) < 5,"turn measures full rotation instead of equivalent heading")
	expect(await run_command("goto",{"x":220,"y":140,"h":50}),"approach card")
	expect(await run_command("goto",{"x":220,"y":140,"h":20}),"descend to card")
	expect(arena.sensor_at(drone.global_position).id == "7-5","bottom sensor")
	expect(await run_command("match"),"match LED")
	expect(await run_command("wait",{"seconds":2.2}),"hover two seconds")
	expect(competition.counts.get("7-5",0) == 1,"physical hover color score")
	expect(await run_command("led",{"color":"white"}),"clear LED")
	expect(await run_command("goto",{"x":40,"y":160,"h":50}),"return pad")
	expect(await run_command("land"),"physical landing")
	for _i in 120: await physics_frame
	expect(not drone.armed and drone.linear_velocity.length() < 0.025,"stationary landing")
	expect(competition.last_landing == 30,"landing judged 30")
	print("MARC_FLIGHT_TEST failures=",failures)
	arena.queue_free()
	drone.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _physics_process(delta: float) -> bool:
	if is_instance_valid(drone) and is_instance_valid(arena):
		competition.tick(delta,drone.global_position,drone.linear_velocity,drone.armed,drone.led,arena.sensor_at(drone.global_position))
	return false
