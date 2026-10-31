extends RefCounted
## Keeps offensive leaderboard names out. A name is folded first (lower case, look-alike digits and
## signs read as letters, everything else dropped, repeated letters squeezed), then checked against
## two lists: PARTS match anywhere in the name, WORDS only as a whole word (they are short and turn
## up inside harmless names: "class", "Dickens", "grape").

const PARTS := [
	"fuck", "fck", "shit", "cunt", "bitch", "biatch", "whore", "slut", "nigg", "niga", "nigr",
	"fag", "fagot", "dyke", "tranny", "retard", "spastic", "pussy", "penis", "vagina", "porn",
	"wank", "twat", "boob", "dildo", "jizz", "bastard", "asshole", "arsehole", "molest",
	"pedo", "paedo", "nazi", "hitler", "heil", "kkk", "rapist", "killyourself",
	"chink", "gook", "kike", "wetback", "paki", "negro", "piss", "horny",
	"kanker", "tering", "hoer", "neuk", "klootzak", "mongool",
	"blyat", "blyad", "suka", "pidor", "pizd", "ebat", "eban", "mudak",
	"блят", "бляд", "сука", "хуй", "хуе", "хуя", "пизд", "ебат", "ебан", "ёб", "пидор", "пидар", "мудак", "шлюх",
]
const WORDS := [
	"ass", "arse", "dick", "cum", "tit", "tits", "sex", "sexy", "rape", "anal", "anus", "homo",
	"kut", "lul", "nig", "fu", "fuk", "stfu", "wtf", "milf", "lesbo", "cock", "kys", "spic", "coon", "bdsm", "nude", "nudes",
]
const LOOK_ALIKE := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
	"@": "a", "$": "s", "!": "i", "|": "i", "+": "t", "€": "e"}


## True when the name looks offensive.
static func blocked(name: String) -> bool:
	var words := []
	for raw in name.to_lower().split(" ", false):
		var plain := _fold(raw)
		if plain != "":
			words.append(plain)
	var joined := "".join(words)
	for variant in [joined, _squeeze(joined)]:
		for part in PARTS:
			if part in variant:
				return true
	for w in words + [joined]:
		if w in WORDS or _squeeze(w) in WORDS:
			return true
	return false


## Letters only, with look-alike digits and signs read as the letter they stand for.
static func _fold(word: String) -> String:
	var out := ""
	for ch in word:
		ch = LOOK_ALIKE.get(ch, ch)
		if ch.to_upper() != ch.to_lower():  # a letter in any script
			out += ch
	return out


## "fuuuck" -> "fuck".
static func _squeeze(word: String) -> String:
	var out := ""
	for ch in word:
		if out == "" or out[-1] != ch:
			out += ch
	return out
