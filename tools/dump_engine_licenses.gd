extends SceneTree
## Godot 本体と、エンジンに組み込まれたサードパーティの部品（Jolt・FreeType・ENet など）の
## 著作権表示とライセンス本文を JSON に書き出す。`tools/check_submission.py` が LICENSES.txt を
## 作る・確かめるときに呼ぶ（エンジンの版が変わっても、その版の一覧から作り直せるように）。
##   godot --headless --script res://tools/dump_engine_licenses.gd -- out.json


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "engine_licenses.json"
	var data := {
		"version": Engine.get_version_info().get("string", ""),
		"godot_license": Engine.get_license_text(),
		"copyright": Engine.get_copyright_info(),
		"licenses": Engine.get_license_info(),
	}
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % out)
		quit(1)
		return
	file.store_string(JSON.stringify(data, " ", false))
	file.close()
	quit()
