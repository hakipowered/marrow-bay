class_name Outfits
extends RefCounted
## Outfit catalogue. Every outfit is its own rigged, textured Meshy model
## (real clothing geometry, not a recolor) that shares the base skeleton
## layout, so all the survivor clips play on it.
##
##   res://assets/characters/<character>/outfits/<id>/<id>.glb
##   res://assets/characters/<character>/outfits/<id>/<id>_anims.res
##
## The clip library is the base character's, retargeted onto the outfit's
## own bone rest by tools/outfits/import_outfits.gd; it also carries the body
## shaping centres moved onto that skeleton.
## "sole": how far the outfit's soles stand above the floor in the idle pose
## (heels), in metres; the model is lowered by that much. Measured with
## tests/feet_check.gd.

const DEFAULT := "default"

## id -> name shown in the picker, a short line, the tag it is listed under,
## and how much of the base model's built-in body shaping to keep. The
## outfit models were sculpted from renders of the shaped body, so they keep
## little of it and the sliders still work on top.
const CATALOGUE := {
	"zegan": {
		"default": {"name": "Paramedic", "desc": "Night-shift medic jacket, plate carrier and cargo trousers.", "tag": "classic"},
		"biker": {"name": "Road Leather", "desc": "Worn biker jacket, white tee, jeans and work boots.", "tag": "classic", "shape": 0.0},
		"riot": {"name": "Riot Unit", "desc": "Full black riot armour with pads and gloves.", "tag": "classic", "shape": 0.0, "sole": 0.010},
		"night_suit": {"name": "Night Suit", "desc": "Rain-damp three-piece suit and a loosened red tie.", "tag": "classic", "shape": 0.0},
		"beach": {"name": "Beach Day", "desc": "Board shorts, dog tag and sneakers. Nothing else.", "tag": "hot", "shape": 0.0},
	},
	"obcera": {
		"default": {"name": "Courier", "desc": "Red leather jacket, biker trousers and her courier bag.", "tag": "classic"},
		"catsuit": {"name": "Black Catsuit", "desc": "Skin-tight glossy leather, zip down to the collarbone.", "tag": "hot", "shape": 0.0},
		"street_heat": {"name": "Street Heat", "desc": "Cropped tank top, cut-off denim shorts and boots.", "tag": "hot", "shape": 0.0},
		"red_dress": {"name": "Red Dress", "desc": "Tight red satin cocktail dress and heels.", "tag": "hot", "shape": 0.0, "sole": 0.015},
		"beach": {"name": "Beach Day", "desc": "Red bikini, thigh holster and combat boots.", "tag": "hot", "shape": 0.0},
		"midnight_lace": {"name": "Midnight Lace", "desc": "Lace corset, stockings, satin gloves and heeled boots.", "tag": "hot", "shape": 0.0, "sole": 0.032},
	},
}

static func ids(character: String) -> Array:
	return CATALOGUE.get(character, {}).keys()

static func info(character: String, id: String) -> Dictionary:
	return CATALOGUE.get(character, {}).get(id, {})

static func display_name(character: String, id: String) -> String:
	return info(character, id).get("name", id.capitalize())

## Model path for an outfit, or "" when it isn't in this build.
static func model_path(character: String, id: String) -> String:
	if id == DEFAULT or id == "":
		return "res://assets/characters/%s/%s.glb" % [character, character]
	var p := "res://assets/characters/%s/outfits/%s/%s.glb" % [character, id, id]
	return p if ResourceLoader.exists(p) else ""

static func anims_path(character: String, id: String) -> String:
	if id == DEFAULT or id == "":
		return "res://assets/characters/%s/%s_anims.res" % [character, character]
	return "res://assets/characters/%s/outfits/%s/%s_anims.res" % [character, id, id]

## True when the outfit's model ships in this build.
static func available(character: String, id: String) -> bool:
	return model_path(character, id) != "" and ResourceLoader.exists(anims_path(character, id))

## The id to actually wear: falls back to the default look when the save or
## the partner asks for an outfit this build doesn't have.
static func resolve(character: String, id: Variant) -> String:
	var s := str(id) if id != null else DEFAULT
	return s if CATALOGUE.get(character, {}).has(s) and available(character, s) else DEFAULT
