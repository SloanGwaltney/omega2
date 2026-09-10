package main
import "../../engine"

main :: proc() {
	app := engine.new_app()
	defer engine.delete_app(app)
	engine.run_app(app)
}
