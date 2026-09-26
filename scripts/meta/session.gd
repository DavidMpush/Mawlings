extends RefCounted
## Übergabe zwischen Menü und Spielszene (statisch, lebt für die Dauer des Prozesses).

static var pending_config: Dictionary = {}   # vom Menü gesetzt, von Main beim Start gelesen und geleert
static var last_result: Dictionary = {}      # von Main am Run-Ende gesetzt, vom Menü gelesen und geleert
