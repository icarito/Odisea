# scripts/ui/CirclePainter.gd
extends Reference

# Utility to create a circular ImageTexture.
static func create_circle_texture(radius: int, color: Color) -> ImageTexture:
	var size = Vector2(radius * 2, radius * 2)
	var center = Vector2(radius, radius)
	var image = Image.new()
	image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.lock()

	for y in range(size.y):
		for x in range(size.x):
			var dist = Vector2(x, y).distance_to(center)
			if dist < radius:
				image.set_pixel(x, y, color)
			else:
				image.set_pixel(x, y, Color(0,0,0,0)) # Transparent

	image.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(image)
	return texture
