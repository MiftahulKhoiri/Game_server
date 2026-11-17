extends SceneTree
## Laporan kualitas bank soal SD (galat + peringatan pedagogis + cakupan topik×kelas).
## Tidak mengubah apa pun; hanya membaca data/pulau_ilmu.json.
## Jalankan:  godot --headless --path client -s res://tests/sd_bank_report.gd
## Exit code 1 bila ada GALAT (peringatan tidak menggagalkan).

const SdData := preload("res://games/education_sd/scripts/sd_data.gd")
const BankAudit := preload("res://games/education_sd/scripts/engine/bank_audit.gd")


func _initialize() -> void:
	var d := SdData.new()
	d.load_data()
	var res := BankAudit.audit(d.doc.get("questions", []), d)
	print(BankAudit.summary_text(res, true))
	print("\nCakupan soal statis per topik × kelas (+gen = ada pembuat soal otomatis):")
	var rows := {}
	for c in res.coverage:
		var tid := str(c.topic)
		if not rows.has(tid):
			rows[tid] = ["-", "-", "-", "-", "-", "-"]
		rows[tid][int(c.grade) - 1] = str(c.static) + ("+gen" if c.gen else "")
	var ids: Array = rows.keys()
	ids.sort()
	print("  %-18s %8s %8s %8s %8s %8s %8s" % ["topik", "k1", "k2", "k3", "k4", "k5", "k6"])
	for tid in ids:
		var r: Array = rows[tid]
		print("  %-18s %8s %8s %8s %8s %8s %8s" % [tid, r[0], r[1], r[2], r[3], r[4], r[5]])
	quit(1 if not (res.errors as Array).is_empty() else 0)
