// The casino's half of engine.entity_from_json: its own components, named
// under the "casino:" prefix so they can never collide with the engine's.
package main

import "../../../engine"
import "core:encoding/json"
import "core:fmt"

// Loads a "casino:" component onto e. Panics on a name no one owns, because
// a scene that names a component this build does not have is a content bug
// worth failing loudly for.
casino_component_loader :: proc(
	w: ^engine.World,
	e: engine.Entity,
	name: string,
	data: json.Value,
) -> bool {
	g := (^Game)(w.user_ptr)
	switch name {
	case "casino:input":
		engine.pool_add(&g.input, e, InputValues{})
	case "casino:player":
		engine.pool_add(&g.player, e, Player{})
	case "casino:movement":
		return component_load(&g.movement, e, data)
	case "casino:mouse_look":
		return component_load(&g.mouse_look, e, data)
	case "casino:interactor":
		return component_load(&g.interactor, e, data)
	case "casino:slot_machine":
		return component_load(&g.slot_machine, e, data)
	case "casino:patron":
		return component_load(&g.patron, e, data)
	case:
		fmt.panicf("unknown component %q", name)
	}
	return true
}

// Unmarshals data into a zeroed component and adds it to p.
@(private = "file")
component_load :: proc(p: ^engine.Pool($T), e: engine.Entity, data: json.Value) -> bool {
	v: T
	if !engine.component_unmarshal(data, &v) {
		return false
	}
	engine.pool_add(p, e, v)
	return true
}
