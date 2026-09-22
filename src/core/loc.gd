## Localization scaffolding (S55, D-110). Every string the player reads
## passes through here: UI text through `t(source)` (the English source is
## the key), content text through `content(kind, id, path, source)` (the
## key is kind.id.path, e.g. dialogue.sera_recruit.nodes.start.text).
## Tables are `locales` content entries ({name, ui: {source: text},
## content: {key: text}}), so a mod can ship a language; the `pseudo`
## locale is a transform instead of a table, wrapping every string it sees
## in ⟦ ⟧ with accented letters, so anything still in plain letters on a
## screen is a string that did not come through. `untranslated(text)`
## finds those; the pseudo-locale test runs every screen through it.
class_name Loc
extends RefCounted

const DEFAULT := "en"
const PSEUDO := "pseudo"
const OPEN := "⟦"
const CLOSE := "⟧"
const ACCENTS: Dictionary = {
	"a": "å", "b": "ƀ", "c": "ç", "d": "ð", "e": "é", "f": "ƒ", "g": "ğ", "h": "ħ", "i": "ï", "j": "ĵ", "k": "ķ", "l": "ł", "m": "ɱ",
	"n": "ñ", "o": "ö", "p": "þ", "q": "ʠ", "r": "ř", "s": "š", "t": "ŧ", "u": "ü", "v": "ṽ", "w": "ŵ", "x": "ẋ", "y": "ÿ", "z": "ž",
	"A": "Å", "B": "Ɓ", "C": "Ç", "D": "Ð", "E": "É", "F": "Ƒ", "G": "Ğ", "H": "Ħ", "I": "Ï", "J": "Ĵ", "K": "Ķ", "L": "Ł", "M": "Ɱ",
	"N": "Ñ", "O": "Ö", "P": "Þ", "Q": "Ǫ", "R": "Ř", "S": "Š", "T": "Ŧ", "U": "Ü", "V": "Ṽ", "W": "Ŵ", "X": "Ẋ", "Y": "Ÿ", "Z": "Ž",
}
## The text fields of every content kind, for translators and the
## extraction tool: `*` is any key, `[]` any index.
const TEXT_FIELDS: Dictionary = {
	"abilities": ["name", "summary"],
	"achievements": ["name", "summary"],
	"affixes": ["name"],
	"biomes": ["name"],
	"branches": ["name"],
	"buildings": ["name", "levels[].blurb"],
	"classes": ["name", "summary", "resource.name", "resource.summary"],
	"companions": ["name", "short_name", "summary", "scenes[].label"],
	"difficulties": ["name", "summary"],
	"dialogue": ["name", "nodes.*.text", "nodes.*.choices[].text", "lines[].text"],
	"endings": ["name", "summary", "epilogue.*.*", "modifiers[].text"],
	"enemies": ["name"],
	"factions": ["name"],
	"items": ["name", "summary"],
	"lore": ["name", "text", "source"],
	"maps": ["name"],
	"merchants": ["name"],
	"npcs": ["name", "short_name", "summary"],
	"origins": ["name", "summary", "unlock_blurb"],
	"parties": ["name"],
	"pickups": ["name"],
	"quests": ["name", "start_toast", "stages.*.summary", "stages.*.objectives[].text", "stages.*.next_toast", "stages.*.branches[].toast"],
	"races": ["name", "identity"],
	"resources": ["name", "summary"],
	"rules": ["lines[]"],
	"shards": ["name"],
	"subclasses": ["name", "summary"],
	"talents": ["name", "summary"],
	"tiles": ["name"],
}

static var locale: String = DEFAULT
static var tables: Dictionary = {} # locale id -> the locales entry
static var seen: Dictionary = {} # every UI source string asked for, for the extraction tool
static var _by_source: Dictionary = {} # locale id -> {source text: translation}, for content whose key the caller does not know


## Takes the `locales` entries from a registry. Keeps the locale if it still exists.
static func load_from(registry: ContentRegistry) -> void:
	tables = {}
	_by_source = {}
	for e: Dictionary in registry.get_all("locales"):
		tables[String(e["id"])] = e
		var by_source: Dictionary = {}
		var sources := extract_content(registry)
		var table: Dictionary = e.get("content", {})
		for key: String in table:
			if sources.has(key):
				by_source[sources[key]] = table[key]
		_by_source[String(e["id"])] = by_source
	if not tables.has(locale):
		locale = DEFAULT


## Locale ids, English first, then by id; pseudo last.
static func available() -> Array[String]:
	var ids: Array[String] = []
	for id: String in tables:
		if id != DEFAULT and id != PSEUDO:
			ids.append(id)
	ids.sort()
	if tables.has(DEFAULT) or tables.is_empty():
		ids.push_front(DEFAULT)
	if tables.has(PSEUDO):
		ids.append(PSEUDO)
	return ids


## Switches locale; unknown ids fall back to English. Returns the locale in force.
static func set_locale(id: String) -> String:
	locale = id if (id == DEFAULT or tables.has(id)) else DEFAULT
	return locale


static func name_of(id: String) -> String:
	if tables.has(id):
		return String(Dictionary(tables[id]).get("name", id))
	return "English" if id == DEFAULT else id


static func is_pseudo() -> bool:
	return bool(Dictionary(tables.get(locale, {})).get("pseudo", false)) or locale == PSEUDO


## A UI string. The source text is the key; missing means the source.
static func t(source: String) -> String:
	if source.is_empty():
		return source
	seen[source] = true
	if is_pseudo():
		return pseudo(source)
	var ui: Dictionary = Dictionary(tables.get(locale, {})).get("ui", {})
	return String(ui.get(source, source))


## A content string by its key: kind.id.path. Missing means the source.
static func content(kind: String, id: String, path: String, source: String) -> String:
	if source.is_empty():
		return source
	if is_pseudo():
		return pseudo(source)
	var table: Dictionary = Dictionary(tables.get(locale, {})).get("content", {})
	var key := "%s.%s.%s" % [kind, id, path]
	if table.has(key):
		return String(table[key])
	return any(source)


## A content string by its source text alone, for the places that hold a
## string without knowing where it came from (a toast an effect carries,
## a banter line, an epilogue). Missing means the source.
static func any(source: String) -> String:
	if source.is_empty():
		return source
	if is_pseudo():
		return pseudo(source)
	return String(Dictionary(_by_source.get(locale, {})).get(source, source))


## A top-level text field of an entry (name, summary, ...), by its provenance.
static func text(entry: Dictionary, field: String, fallback: String = "") -> String:
	var source := String(entry.get(field, fallback))
	return content(String(entry.get("_kind", "")), String(entry.get("id", "")), field, source)


## The pseudo transform: ⟦ + accented letters + ⟧, format tokens (%s, %d,
## %.1f, %+d, %-18s, %%) left alone so formatting still works.
static func pseudo(source: String) -> String:
	if source.strip_edges().is_empty():
		return source
	var out := ""
	var i := 0
	while i < source.length():
		var ch := source[i]
		if ch == "%":
			var j := i + 1
			while j < source.length() and j - i < 8 and source[j] in ["-", "+", " ", ".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
				j += 1
			if j < source.length() and source[j] in ["s", "d", "f", "x", "c", "%"]:
				out += source.substr(i, j - i + 1) # a format token, kept whole
				i = j + 1
				continue
			out += ch # a plain percent sign ("60% on return")
			i += 1
			continue
		out += String(ACCENTS.get(ch, ch))
		i += 1
	return OPEN + out + CLOSE


## Runs of plain ASCII letters anywhere in a screen's text: the pseudo
## transform accents every letter it sees, so a plain one, inside a frame
## or outside, is a string (or a piece formatted into one) that never came
## through here.
static func untranslated(text: String) -> Array[String]:
	var out: Array[String] = []
	var letters := RegEx.new()
	letters.compile("[A-Za-z]+")
	for m: RegExMatch in letters.search_all(text):
		out.append(m.get_string())
	return out


## Every content string a registry holds, keyed for a locale table:
## {"kind.id.path": source}. Kinds without text fields are skipped.
static func extract_content(registry: ContentRegistry) -> Dictionary:
	var out: Dictionary = {}
	for kind: String in TEXT_FIELDS:
		for e: Dictionary in registry.get_all(kind):
			for pattern: String in TEXT_FIELDS[kind]:
				_walk(e, pattern.split("."), 0, "", func(path: String, value: String) -> void:
					out["%s.%s.%s" % [kind, e["id"], path]] = value)
	return out


static func _walk(node: Variant, parts: PackedStringArray, depth: int, path: String, found: Callable) -> void:
	if depth >= parts.size():
		if node is String and not String(node).strip_edges().is_empty():
			found.call(path, String(node))
		return
	var part := parts[depth]
	var is_array := part.ends_with("[]")
	var key := part.trim_suffix("[]")
	var next: Variant = null
	if key == "*":
		if node is Dictionary:
			for k: Variant in (node as Dictionary):
				_walk((node as Dictionary)[k], parts, depth + 1, _join(path, String(k)), found)
		return
	if node is Dictionary:
		next = (node as Dictionary).get(key, null)
	if next == null:
		return
	if is_array:
		if next is Array:
			var arr: Array = next
			for i: int in arr.size():
				_walk(arr[i], parts, depth + 1, _join(path, "%s.%d" % [key, i]), found)
		return
	_walk(next, parts, depth + 1, _join(path, key), found)


static func _join(path: String, part: String) -> String:
	return part if path.is_empty() else path + "." + part
