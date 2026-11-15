extends "res://shared/edu/quiz_app.gd"
## Game Pembelajaran SD (paket unduhan). Mesin kuis: res://shared/edu/quiz_app.gd (ikut APK launcher).
## Isi pelajaran: res://games/education_sd/data/course.json (dibuat oleh tools/gamepack/make_courses.py).


func _init() -> void:
	game_id = "education_sd"
	course_path = "res://games/education_sd/data/course.json"
