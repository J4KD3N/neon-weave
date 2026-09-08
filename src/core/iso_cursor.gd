## Maps a screen-space direction (stick, D-pad, WASD) to one grid step on
## the diamond-down isometric grid, so "up" on the pad moves the cursor up
## on screen rather than up the grid axis.
class_name IsoCursor
extends RefCounted

## Grid steps by screen angle in 45° slices, starting at screen-right and
## turning clockwise (y down): right, down-right, down, down-left, left,
## up-left, up, up-right.
const STEPS: Array[Vector2i] = [
	Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1),
	Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1),
]
const DEAD_ZONE := 0.25


static func step(dir: Vector2) -> Vector2i:
	if dir.length_squared() < DEAD_ZONE * DEAD_ZONE:
		return Vector2i.ZERO
	var angle := fposmod(rad_to_deg(dir.angle()), 360.0)
	return STEPS[int(round(angle / 45.0)) % 8]
