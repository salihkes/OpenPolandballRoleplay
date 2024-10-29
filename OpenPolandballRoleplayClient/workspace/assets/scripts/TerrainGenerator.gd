extends Resource
class_name TerrainGenerator

# Export variables allow editing in the Inspector
export var grid_size: int = 100
export var max_height: float = 4.0
export var cell_width: float = 3.0
export var cell_height: float = 3.0

var block_scene: PackedScene
var water_scene: PackedScene
var workspace: Node
var heightmap: Image

const COLORS = {
	"grass": Color("4b974b"),
	"rock": Color("635f62"),
	"sand": Color("fdea8d"),
	"soil": Color("a05f35"),
	"water": Color("2154b9"),
	"blackish": Color("1a1a1a")
}

# Modify the _init function to include heightmap
func _init(p_workspace: Node, p_block_scene: PackedScene, p_water_scene: PackedScene, p_heightmap: Image):
	workspace = p_workspace
	block_scene = p_block_scene
	water_scene = p_water_scene
	heightmap = p_heightmap

func generate():
	var grid_offset = Vector3(-grid_size / 2 * cell_width, 0, -grid_size / 2 * cell_width)
	var positions = _calculate_terrain_positions()
	_place_terrain_blocks(positions, grid_offset)
	_place_water_blocks(positions, grid_offset)
	workspace.call_deferred("propagate_call", "queue_sort")

func _calculate_terrain_positions() -> Array:
	var positions = []
	for x in range(grid_size):
		for z in range(grid_size):
			var height = _get_height_from_heightmap(x, z, max_height)
			positions.append({ "x": x, "z": z, "height": height })
	return positions

func _place_terrain_blocks(positions: Array, grid_offset: Vector3):
	for pos in positions:
		var x = pos["x"]
		var z = pos["z"]
		var height = pos["height"]
		
		for y in range(int(height) + 1):
			var grid_position = Vector3(
				x * cell_width, 
				y * cell_height, 
				z * cell_width
			) + grid_offset
			
			var part_instance = block_scene.instance()
			part_instance.transform.origin = _snap_to_grid(grid_position)
			
			var color = _get_block_color(y)
			_color_part(part_instance, color)
			workspace.add_child(part_instance, false)

func _get_block_color(height: int) -> Color:
	if height == 0:
		return COLORS["blackish"]
	elif height < 1:
		return COLORS["soil"]
	elif height < 2:
		return COLORS["sand"]
	elif height < 3:
		return COLORS["grass"]
	else:
		return COLORS["rock"]

func _place_water_blocks(positions: Array, grid_offset: Vector3):
	for pos in positions:
		var x = pos["x"]
		var z = pos["z"]
		var height = pos["height"]
		
		if height < 2:
			for water_level in range(int(height) + 1, 2):
				var water_position = Vector3(
					x * cell_width, 
					water_level * cell_height, 
					z * cell_width
				) + grid_offset
				
				var water_instance = water_scene.instance()
				water_instance.transform.origin = _snap_to_grid(water_position)
				_color_part(water_instance, COLORS["water"])
				workspace.add_child(water_instance)

func _snap_to_grid(pos: Vector3) -> Vector3:
	return Vector3(
		stepify(pos.x, cell_width),
		stepify(pos.y, cell_height),
		stepify(pos.z, cell_width)
	)

func _color_part(part: Node, color: Color):
	if part.has_node("Mesh"):
		var mesh = part.get_node("Mesh")
		var material = mesh.get_surface_material(0)
		if material:
			material = material.duplicate()
			material.albedo_color = color
			mesh.set_surface_material(0, material)

func _get_height_from_heightmap(x: int, z: int, max_height: float) -> float:
	var img_x = int((float(x) / grid_size) * heightmap.get_width())
	var img_z = int((float(z) / grid_size) * heightmap.get_height())

	var pixel_value = heightmap.get_pixel(img_x, img_z).r

	return pixel_value * max_height
