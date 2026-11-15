extends "res://shared/edu/quiz_app.gd"
## Game Pembelajaran SMP (paket unduhan). Mesin kuis: res://shared/edu/quiz_app.gd (ikut APK launcher).
## Isi pelajaran: res://games/education_smp/data/course.json (dibuat oleh tools/gamepack/make_courses.py).


func _init() -> void:
	game_id = "education_smp"
	course_path = "res://games/education_smp/data/course.json"
