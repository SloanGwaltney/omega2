package main
import "../../engine"
import "core:fmt"

main :: proc() {
	app := engine.new_app()
	defer engine.delete_app(app)
	fmt.println("Hello World")
}
