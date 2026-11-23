class_name CrawlBalanceMonitor
extends ClimbBalanceMonitor
## ClimbBalanceMonitor (Lesson 15) with the crawl's contacts as support
## (Lesson 16).
##
## How the files relate:
##   BalanceMonitor (Lesson 13)       center of mass, polygon of the feet,
##                                    margin, state, OSC
##   ClimbBalanceMonitor (Lesson 15)  the held contacts while climbing
##   CrawlController                  contact_points(): every planted hand,
##     (crawl_controller.gd)          knee (crawl) or foot (scramble)
##   this file                        while crawling or scrambling, rebuilds
##                                    the polygon from those contacts
##
## The polygon has four corners while all limbs stand and three while one
## swings. Its ground projection (Lesson 13: (x, -z), the heights dropped)
## is what the center of mass must lie over; on a slab the corners lie at
## different heights, and the projection shortens the polygon along the
## slope by cos(slope) (README P5). The OSC messages of Lesson 13 carry the
## new margin unchanged.

## The crawl to read. The scene assigns it.
@export var crawl: CrawlController

## Corners of the polygon in the last measurement (0 when not crawling).
var support_count := 0


func measure() -> void:
	super()
	support_count = 0
	if crawl == null or not crawl.is_active():
		return
	var corners := PackedVector2Array()
	var height_sum := 0.0
	for contact in crawl.contact_points():
		var point: Vector3 = contact[0]
		corners.append(SupportPolygon.ground_point(point))
		height_sum += point.y
	support_count = corners.size()
	polygon = SupportPolygon.convex_hull(corners)
	polygon_height = height_sum / corners.size() if corners.size() > 0 else center_of_mass.y - center_height
	margin = SupportPolygon.signed_distance(polygon, SupportPolygon.ground_point(center_of_mass))
	state = next_state(state, margin, not polygon.is_empty(), marginal_margin, hysteresis)
