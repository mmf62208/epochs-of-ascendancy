# scripts/ui/RoutePackQR.gd
## Pass 32/33: pure GDScript QR encoder (byte mode, ECC M) — no qrencode CLI required.
## Supports versions 1–20 (long EORP2/EORP3 share codes).
class_name RoutePackQR
extends RefCounted

## Max version supported by this encoder.
const MAX_VERSION := 20
## Pass 34: target outer size (px) when auto-sizing module pixels for EORP3 QR.
const AUTO_TARGET_SIDE_PX := 248


## Pass 34: choose module pixel size so QR outer side ≈ target_side.
## matrix_n = modules on a side (without quiet zone). Returns clamped 2–10.
static func auto_module_px(matrix_n: int, target_side: int = AUTO_TARGET_SIDE_PX, margin: int = 2) -> int:
	if matrix_n <= 0:
		return 5
	var denom: int = matrix_n + maxi(0, margin) * 2
	var px: int = int(round(float(maxi(1, target_side)) / float(denom)))
	return clampi(px, 2, 10)


## Encode text → Image (black modules on white). Returns null on failure.
## module_px ≤ 0 → Pass 34 auto size toward AUTO_TARGET_SIDE_PX.
static func encode_to_image(text: String, module_px: int = 5, margin: int = 2) -> Image:
	var matrix := encode_matrix(text)
	if matrix.is_empty():
		return null
	var n: int = matrix.size()
	var m := maxi(0, margin)
	var px := module_px
	if px <= 0:
		px = auto_module_px(n, AUTO_TARGET_SIDE_PX, m)
	px = maxi(1, px)
	var side := (n + m * 2) * px
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for y in n:
		var row: Array = matrix[y]
		for x in n:
			if bool(row[x]):
				var ox := (x + m) * px
				var oy := (y + m) * px
				for dy in px:
					for dx in px:
						img.set_pixel(ox + dx, oy + dy, Color.BLACK)
	return img


## Encode text → user:// PNG path, or "" on failure.
## module_px ≤ 0 → auto-size (Pass 34).
static func encode_to_user_png(text: String, path: String = "user://route_pack_qr.png", module_px: int = -1, margin: int = 2) -> String:
	var img := encode_to_image(text, module_px, margin)
	if img == null:
		return ""
	var abs_path := ProjectSettings.globalize_path(path)
	var err := img.save_png(abs_path)
	if err != OK:
		return ""
	return path


## Byte capacity for ECC M (usable data bytes after mode+count overhead).
static func capacity_bytes(ver: int) -> int:
	# Net data-byte capacity for byte mode ECC M, versions 1–20.
	var capacity_m := [
		0,
		14, 26, 42, 62, 84, 106, 122, 152, 180, 213,  # 1–10
		251, 287, 331, 362, 412, 450, 504, 560, 624, 666,  # 11–20
	]
	if ver < 1 or ver >= capacity_m.size():
		return 0
	return int(capacity_m[ver])


## Returns n×n nested Array of bools (true = dark module), or empty on failure.
static func encode_matrix(text: String) -> Array:
	var data := text.to_utf8_buffer()
	if data.is_empty():
		data = PackedByteArray([0])
	var ver := 0
	var need: int = data.size()
	for v in range(1, MAX_VERSION + 1):
		if need <= capacity_bytes(v):
			ver = v
			break
	if ver == 0:
		return []
	return _build_qr(data, ver)


# --- Reed-Solomon / GF(256) ---
static var _gf_exp: PackedInt32Array = PackedInt32Array()
static var _gf_log: PackedInt32Array = PackedInt32Array()
static var _gf_ready: bool = false

static func _ensure_gf() -> void:
	if _gf_ready:
		return
	_gf_exp.resize(512)
	_gf_log.resize(256)
	var x := 1
	for i in 255:
		_gf_exp[i] = x
		_gf_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11d
	for i in range(255, 512):
		_gf_exp[i] = _gf_exp[i - 255]
	_gf_log[0] = 0
	_gf_ready = true


static func _gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _gf_exp[_gf_log[a] + _gf_log[b]]


static func _gf_poly_mul(p: PackedByteArray, q: PackedByteArray) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(p.size() + q.size() - 1)
	for i in p.size():
		for j in q.size():
			r[i + j] = r[i + j] ^ _gf_mul(p[i], q[j])
	return r


static func _rs_generator(ec_len: int) -> PackedByteArray:
	_ensure_gf()
	var g := PackedByteArray([1])
	for i in ec_len:
		var term := PackedByteArray([1, _gf_exp[i]])
		g = _gf_poly_mul(g, term)
	return g


static func _rs_encode(data: PackedByteArray, ec_len: int) -> PackedByteArray:
	_ensure_gf()
	var gen := _rs_generator(ec_len)
	var msg := PackedByteArray()
	msg.resize(data.size() + ec_len)
	for i in data.size():
		msg[i] = data[i]
	for i in data.size():
		var coef := msg[i]
		if coef != 0:
			for j in range(1, gen.size()):
				msg[i + j] = msg[i + j] ^ _gf_mul(gen[j], coef)
	var ec := PackedByteArray()
	ec.resize(ec_len)
	for i in ec_len:
		ec[i] = msg[data.size() + i]
	return ec


static func _gf_div(a: int, b: int) -> int:
	if b == 0 or a == 0:
		return 0
	return _gf_exp[(_gf_log[a] - _gf_log[b] + 255) % 255]


static func _gf_inv(a: int) -> int:
	if a == 0:
		return 0
	return _gf_exp[255 - _gf_log[a]]


## poly[0] = highest-degree coefficient.
static func _poly_eval_hi(poly: PackedByteArray, x: int) -> int:
	var y := 0
	for i in poly.size():
		y = _gf_mul(y, x) ^ int(poly[i])
	return y


## poly[0] = constant (lowest degree).
static func _poly_eval_lo(poly: PackedByteArray, x: int) -> int:
	var y := 0
	for i in range(poly.size() - 1, -1, -1):
		y = _gf_mul(y, x) ^ int(poly[i])
	return y


static func _poly_mul_lo(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	if a.is_empty() or b.is_empty():
		return PackedByteArray()
	var r := PackedByteArray()
	r.resize(a.size() + b.size() - 1)
	for i in a.size():
		for j in b.size():
			r[i + j] = int(r[i + j]) ^ _gf_mul(int(a[i]), int(b[j]))
	return r


## Pass 63: RS correct one systematic block (data||ec). Returns data only, or empty if fail.
static func _rs_correct_block(block: PackedByteArray, data_len: int, ec_len: int) -> PackedByteArray:
	_ensure_gf()
	if data_len <= 0 or ec_len <= 0 or block.size() < data_len + ec_len:
		return PackedByteArray()
	var n: int = data_len + ec_len
	var recv := PackedByteArray()
	recv.resize(n)
	for i in n:
		recv[i] = block[i]
	# Syndromes (generator roots alpha^0 .. alpha^{ec_len-1}).
	var synd := PackedByteArray()
	synd.resize(ec_len)
	var has_err := false
	for i in ec_len:
		var root := 1 if i == 0 else _gf_exp[i]
		var s := _poly_eval_hi(recv, root)
		synd[i] = s
		if s != 0:
			has_err = true
	if not has_err:
		return recv.slice(0, data_len)
	# Berlekamp–Massey (Λ low-order, Λ[0]=1).
	var lam := PackedByteArray([1])
	var prev := PackedByteArray([1])
	var L := 0
	var m_shift := 1
	var b_scale := 1
	for r in ec_len:
		var delta := int(synd[r])
		for j in range(1, L + 1):
			if j < lam.size():
				delta ^= _gf_mul(int(lam[j]), int(synd[r - j]))
		if delta == 0:
			m_shift += 1
			continue
		var lam_copy := lam.duplicate()
		var coef := _gf_div(delta, b_scale)
		var need := m_shift + prev.size()
		if lam.size() < need:
			lam.resize(need)
		for j2 in prev.size():
			lam[j2 + m_shift] = int(lam[j2 + m_shift]) ^ _gf_mul(coef, int(prev[j2]))
		if 2 * L <= r:
			prev = lam_copy
			b_scale = delta
			L = r + 1 - L
			m_shift = 1
		else:
			m_shift += 1
	# Degree of locator.
	while lam.size() > 1 and int(lam[lam.size() - 1]) == 0:
		lam.resize(lam.size() - 1)
	var deg := lam.size() - 1
	if deg <= 0 or deg > (ec_len / 2) + 1:
		# Allow up to floor(ec_len/2) typically; keep soft cap.
		if deg <= 0 or deg > ec_len:
			return PackedByteArray()
	# Chien search: Λ(α^k)==0 ⇒ error at index n-1-k (high-first).
	var err_pos: Array = []
	for k in n:
		var xk := 1 if k == 0 else _gf_exp[k]
		if _poly_eval_lo(lam, xk) == 0:
			var idx := n - 1 - k
			if idx >= 0 and idx < n:
				err_pos.append(idx)
	if err_pos.is_empty() or err_pos.size() > ec_len:
		return PackedByteArray()
	# Ω(x) = S(x)*Λ(x) mod x^{ec_len} (low-order).
	var omega := PackedByteArray()
	omega.resize(ec_len)
	for i2 in synd.size():
		for j3 in lam.size():
			if i2 + j3 >= ec_len:
				break
			omega[i2 + j3] = int(omega[i2 + j3]) ^ _gf_mul(int(synd[i2]), int(lam[j3]))
	# Formal derivative of Λ (low-order): only odd powers survive in char 2.
	var lam_d := PackedByteArray()
	lam_d.resize(maxi(lam.size() - 1, 1))
	for j4 in range(1, lam.size()):
		if j4 % 2 == 1:
			lam_d[j4 - 1] = lam[j4]
	# Forney: e_i = Ω(X_i) / Λ'(X_i) with X_i = α^{n-1-pos}
	for pos_v in err_pos:
		var pos: int = int(pos_v)
		var k_pos := n - 1 - pos
		var x_err := 1 if k_pos == 0 else _gf_exp[k_pos]
		var num := _poly_eval_lo(omega, x_err)
		var den := _poly_eval_lo(lam_d, x_err)
		if den == 0:
			return PackedByteArray()
		recv[pos] = int(recv[pos]) ^ _gf_div(num, den)
	# Re-check syndromes.
	for i3 in ec_len:
		var root := 1 if i3 == 0 else _gf_exp[i3]
		if _poly_eval_hi(recv, root) != 0:
			return PackedByteArray()
	return recv.slice(0, data_len)

# ECC-M: total codewords, EC codewords, block count (g1 short / g2 long)
# Format: [total_cw, ec_cw_per_block, num_blocks_g1, data_cw_g1, num_blocks_g2, data_cw_g2]
# Derived from ISO/IEC 18004 via Nayuki block tables (versions 1–20).
static func _ecc_m_table(ver: int) -> Array:
	match ver:
		1: return [26, 10, 1, 16, 0, 0]
		2: return [44, 16, 1, 28, 0, 0]
		3: return [70, 26, 1, 44, 0, 0]
		4: return [100, 18, 2, 32, 0, 0]
		5: return [134, 24, 2, 43, 0, 0]
		6: return [172, 16, 4, 27, 0, 0]
		7: return [196, 18, 4, 31, 0, 0]
		8: return [242, 22, 2, 38, 2, 39]
		9: return [292, 22, 3, 36, 2, 37]
		10: return [346, 26, 4, 43, 1, 44]
		11: return [404, 30, 1, 50, 4, 51]
		12: return [466, 22, 6, 36, 2, 37]
		13: return [532, 22, 8, 37, 1, 38]
		14: return [581, 24, 4, 40, 5, 41]
		15: return [655, 24, 5, 41, 5, 42]
		16: return [733, 28, 7, 45, 3, 46]
		17: return [815, 28, 10, 46, 1, 47]
		18: return [901, 26, 9, 43, 4, 44]
		19: return [991, 26, 3, 44, 11, 45]
		20: return [1085, 26, 3, 41, 13, 42]
		_: return [26, 10, 1, 16, 0, 0]


static func _encode_data_bits(data: PackedByteArray, ver: int, data_cw: int) -> PackedByteArray:
	var bits: Array = []  # 0/1 ints
	# Mode: byte = 0100
	bits.append_array([0, 1, 0, 0])
	var count_bits := 8 if ver <= 9 else 16
	var n := data.size()
	for i in range(count_bits - 1, -1, -1):
		bits.append((n >> i) & 1)
	for b in data:
		for i in range(7, -1, -1):
			bits.append((int(b) >> i) & 1)
	# Terminator
	var capacity_bits := data_cw * 8
	var term := mini(4, capacity_bits - bits.size())
	for _i in term:
		bits.append(0)
	# Pad to byte
	while bits.size() % 8 != 0:
		bits.append(0)
	# Pad codewords 0xEC / 0x11
	var pad_toggle := true
	while bits.size() / 8 < data_cw:
		var padv := 0xEC if pad_toggle else 0x11
		pad_toggle = not pad_toggle
		for i in range(7, -1, -1):
			bits.append((padv >> i) & 1)
	var out := PackedByteArray()
	out.resize(data_cw)
	for i in data_cw:
		var v := 0
		for j in 8:
			v = (v << 1) | int(bits[i * 8 + j])
		out[i] = v
	return out


static func _interleave(data: PackedByteArray, ver: int) -> PackedByteArray:
	var t: Array = _ecc_m_table(ver)
	var ec_per: int = t[1]
	var n1: int = t[2]
	var d1: int = t[3]
	var n2: int = t[4]
	var d2: int = t[5]
	var blocks: Array = []  # each {data: PackedByteArray, ec: PackedByteArray}
	var offset := 0
	for _b in n1:
		var blk := data.slice(offset, offset + d1)
		offset += d1
		blocks.append({"data": blk, "ec": _rs_encode(blk, ec_per)})
	for _b in n2:
		var blk2 := data.slice(offset, offset + d2)
		offset += d2
		blocks.append({"data": blk2, "ec": _rs_encode(blk2, ec_per)})
	var max_d := d1 if n2 == 0 else maxi(d1, d2)
	var result := PackedByteArray()
	for i in max_d:
		for blk in blocks:
			var bd: PackedByteArray = blk["data"]
			if i < bd.size():
				result.append(bd[i])
	for i in ec_per:
		for blk in blocks:
			var be: PackedByteArray = blk["ec"]
			result.append(be[i])
	return result


static func _size_for_ver(ver: int) -> int:
	return 17 + 4 * ver


static func _set_module(mat: Array, x: int, y: int, dark: bool, locked: Array) -> void:
	var n: int = mat.size()
	if x < 0 or y < 0 or x >= n or y >= n:
		return
	if locked[y][x]:
		return
	mat[y][x] = dark
	locked[y][x] = true


static func _force_module(mat: Array, x: int, y: int, dark: bool, locked: Array) -> void:
	var n: int = mat.size()
	if x < 0 or y < 0 or x >= n or y >= n:
		return
	mat[y][x] = dark
	locked[y][x] = true


static func _place_finder(mat: Array, locked: Array, ox: int, oy: int) -> void:
	for dy in 7:
		for dx in 7:
			var edge := dx == 0 or dx == 6 or dy == 0 or dy == 6
			var core := dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4
			_force_module(mat, ox + dx, oy + dy, edge or core, locked)
	# Separator (white)
	for i in 8:
		_force_module(mat, ox - 1, oy + i, false, locked)
		_force_module(mat, ox + 7, oy + i, false, locked)
		_force_module(mat, ox + i, oy - 1, false, locked)
		_force_module(mat, ox + i, oy + 7, false, locked)
	_force_module(mat, ox - 1, oy - 1, false, locked)
	_force_module(mat, ox + 7, oy - 1, false, locked)
	_force_module(mat, ox - 1, oy + 7, false, locked)
	_force_module(mat, ox + 7, oy + 7, false, locked)


static func _place_timing(mat: Array, locked: Array) -> void:
	var n: int = mat.size()
	for i in n:
		if not locked[6][i]:
			_force_module(mat, i, 6, i % 2 == 0, locked)
		if not locked[i][6]:
			_force_module(mat, 6, i, i % 2 == 0, locked)


static func _alignment_centers(ver: int) -> Array:
	if ver == 1:
		return []
	# Formula from ISO / Nayuki (versions 2–20), ascending.
	var size := _size_for_ver(ver)
	var numalign: int = int(ver / 7) + 2
	var step: int = int((ver * 8 + numalign * 3 + 5) / (numalign * 4 - 4)) * 2
	var rev: Array = []
	for i in range(numalign - 1):
		rev.append(size - 7 - i * step)
	rev.append(6)
	var centers: Array = []
	for i in range(rev.size() - 1, -1, -1):
		centers.append(rev[i])
	return centers


static func _place_alignment(mat: Array, locked: Array, ver: int) -> void:
	var centers: Array = _alignment_centers(ver)
	var n: int = mat.size()
	for cy in centers:
		for cx in centers:
			# Skip if overlaps finder
			if (cx <= 8 and cy <= 8) or (cx >= n - 9 and cy <= 8) or (cx <= 8 and cy >= n - 9):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var adx := absi(dx)
					var ady := absi(dy)
					var dark := adx == 2 or ady == 2 or (dx == 0 and dy == 0)
					_force_module(mat, cx + dx, cy + dy, dark, locked)


static func _place_dark_module(mat: Array, locked: Array, ver: int) -> void:
	_force_module(mat, 8, 4 * ver + 9, true, locked)


static func _reserve_format(mat: Array, locked: Array) -> void:
	var n: int = mat.size()
	for i in 9:
		if i != 6:
			locked[8][i] = true
			locked[i][8] = true
	for i in 8:
		locked[8][n - 1 - i] = true
		locked[n - 1 - i][8] = true


## Pass 33: reserve + draw version info blocks (required for versions ≥ 7).
static func _reserve_version(mat: Array, locked: Array, ver: int) -> void:
	if ver < 7:
		return
	var n: int = mat.size()
	for i in 6:
		for j in 3:
			locked[i][n - 11 + j] = true
			locked[n - 11 + j][i] = true


static func _draw_version(mat: Array, ver: int) -> void:
	if ver < 7:
		return
	var rem := ver
	for _i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	var bits := (ver << 12) | rem
	var n: int = mat.size()
	for i in 18:
		var dark := ((bits >> i) & 1) == 1
		var a := n - 11 + (i % 3)
		var b := int(i / 3)
		mat[b][a] = dark
		mat[a][b] = dark


static func _bits_to_modules(mat: Array, locked: Array, codewords: PackedByteArray) -> void:
	var n: int = mat.size()
	var bit_idx := 0
	var total_bits := codewords.size() * 8
	var col := n - 1
	var upward := true
	while col > 0:
		if col == 6:
			col -= 1
		var rows: Array = []
		if upward:
			for r in range(n - 1, -1, -1):
				rows.append(r)
		else:
			for r in n:
				rows.append(r)
		for row in rows:
			for c_off in [0, -1]:
				var x: int = col + c_off
				var y: int = row
				if locked[y][x]:
					continue
				var dark := false
				if bit_idx < total_bits:
					var b := int(codewords[bit_idx >> 3])
					dark = ((b >> (7 - (bit_idx & 7))) & 1) == 1
					bit_idx += 1
				mat[y][x] = dark
				# leave unlocked for mask apply
		upward = not upward
		col -= 2


static func _apply_mask(mat: Array, locked: Array, mask: int) -> Array:
	var n: int = mat.size()
	var out: Array = []
	for y in n:
		var row: Array = []
		for x in n:
			var v: bool = mat[y][x]
			if not locked[y][x]:
				var flip := false
				match mask:
					0: flip = (x + y) % 2 == 0
					1: flip = y % 2 == 0
					2: flip = x % 3 == 0
					3: flip = (x + y) % 3 == 0
					4: flip = (int(y / 2) + int(x / 3)) % 2 == 0
					5: flip = ((x * y) % 2 + (x * y) % 3) == 0
					6: flip = (((x * y) % 2 + (x * y) % 3) % 2) == 0
					7: flip = (((x + y) % 2 + (x * y) % 3) % 2) == 0
				if flip:
					v = not v
			row.append(v)
		out.append(row)
	return out


static func _format_bits(ecc_m: int, mask: int) -> int:
	# ECC M = 00
	var data := ((ecc_m & 0x3) << 3) | (mask & 0x7)
	var bits := data << 10
	var poly := 0x537
	for i in range(4, -1, -1):
		if bits & (1 << (i + 10)):
			bits ^= poly << i
	var fmt := ((data << 10) | bits) ^ 0x5412
	return fmt & 0x7FFF


static func _draw_format(mat: Array, mask: int) -> void:
	var fmt := _format_bits(0, mask)  # ECC M = 0
	var n: int = mat.size()
	var positions_a := [
		[0, 8], [1, 8], [2, 8], [3, 8], [4, 8], [5, 8], [7, 8], [8, 8],
		[8, 7], [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0],
	]
	var positions_b := [
		[n - 1, 8], [n - 2, 8], [n - 3, 8], [n - 4, 8], [n - 5, 8], [n - 6, 8], [n - 7, 8], [n - 8, 8],
		[8, n - 7], [8, n - 6], [8, n - 5], [8, n - 4], [8, n - 3], [8, n - 2], [8, n - 1],
	]
	for i in 15:
		var dark := ((fmt >> (14 - i)) & 1) == 1
		var pa: Array = positions_a[i]
		var pb: Array = positions_b[i]
		mat[pa[1]][pa[0]] = dark
		mat[pb[1]][pb[0]] = dark


static func _penalty(mat: Array) -> int:
	var n: int = mat.size()
	var score := 0
	# N1: runs of 5+
	for y in n:
		var run := 1
		for x in range(1, n):
			if mat[y][x] == mat[y][x - 1]:
				run += 1
			else:
				if run >= 5:
					score += 3 + (run - 5)
				run = 1
		if run >= 5:
			score += 3 + (run - 5)
	for x in n:
		var run2 := 1
		for y in range(1, n):
			if mat[y][x] == mat[y - 1][x]:
				run2 += 1
			else:
				if run2 >= 5:
					score += 3 + (run2 - 5)
				run2 = 1
		if run2 >= 5:
			score += 3 + (run2 - 5)
	# N2: 2×2 blocks
	for y in range(n - 1):
		for x in range(n - 1):
			var v = mat[y][x]
			if v == mat[y][x + 1] and v == mat[y + 1][x] and v == mat[y + 1][x + 1]:
				score += 3
	# N4: dark proportion
	var dark := 0
	for y in n:
		for x in n:
			if mat[y][x]:
				dark += 1
	var pct := int(100.0 * float(dark) / float(n * n))
	score += absi(pct - 50) / 5 * 10
	return score


static func _build_qr(data: PackedByteArray, ver: int) -> Array:
	var t: Array = _ecc_m_table(ver)
	var n1: int = t[2]
	var d1: int = t[3]
	var n2: int = t[4]
	var d2: int = t[5]
	var data_cw := n1 * d1 + n2 * d2
	if data.size() > data_cw:
		return []
	var data_codewords := _encode_data_bits(data, ver, data_cw)
	var final_cw := _interleave(data_codewords, ver)
	var n := _size_for_ver(ver)
	var mat: Array = []
	var locked: Array = []
	for y in n:
		var row: Array = []
		var lrow: Array = []
		for x in n:
			row.append(false)
			lrow.append(false)
		mat.append(row)
		locked.append(lrow)
	_place_finder(mat, locked, 0, 0)
	_place_finder(mat, locked, n - 7, 0)
	_place_finder(mat, locked, 0, n - 7)
	_place_timing(mat, locked)
	_place_alignment(mat, locked, ver)
	_place_dark_module(mat, locked, ver)
	_reserve_format(mat, locked)
	_reserve_version(mat, locked, ver)
	_bits_to_modules(mat, locked, final_cw)
	var best_mat: Array = []
	var best_score := 1 << 30
	for mask in 8:
		var masked := _apply_mask(mat, locked, mask)
		_draw_format(masked, mask)
		_draw_version(masked, ver)
		var sc := _penalty(masked)
		if sc < best_score:
			best_score = sc
			best_mat = masked
	return best_mat


# =============================================================================
# Pass 62/63/64: pure GDScript QR decoder (byte mode, ECC M) for clean engine PNGs.
# Prefer this path; MapRenderer falls back to zbarimg when engine decode fails.
# =============================================================================

## Pass 64: stats from last successful/failed engine decode attempt.
static var last_decode_stats: Dictionary = {
	"ok": false,
	"blocks": 0,
	"blocks_clean": 0,
	"blocks_corrected": 0,
	"blocks_raw_fallback": 0,
	"source": "",
}


static func get_last_decode_stats() -> Dictionary:
	return last_decode_stats.duplicate(true)


static func _reset_decode_stats(source: String = "") -> void:
	last_decode_stats = {
		"ok": false,
		"blocks": 0,
		"blocks_clean": 0,
		"blocks_corrected": 0,
		"blocks_raw_fallback": 0,
		"source": source,
	}


## Decode text from Image. Returns "" on failure.
static func decode_from_image(img: Image) -> String:
	_reset_decode_stats("image")
	if img == null or img.get_width() < 21 or img.get_height() < 21:
		return ""
	var work := img
	if work.get_format() != Image.FORMAT_RGBA8 and work.get_format() != Image.FORMAT_RGB8:
		work = img.duplicate()
		work.convert(Image.FORMAT_RGBA8)
	# Pass 64: try mild anisotropic/shear unwarp samples first, then plain.
	var mat := _sample_matrix_from_image(work)
	if mat.is_empty():
		return ""
	var text := decode_from_matrix(mat)
	if not text.is_empty():
		last_decode_stats["ok"] = true
	return text


## Decode text from PNG path (user:// or absolute). Returns "" on failure.
static func decode_from_path(path: String) -> String:
	var pth := path.strip_edges()
	if pth.is_empty():
		_reset_decode_stats("path")
		return ""
	var abs_path := pth
	if pth.begins_with("user://") or pth.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(pth)
	if not FileAccess.file_exists(abs_path):
		if FileAccess.file_exists(pth):
			abs_path = pth
		else:
			_reset_decode_stats("path")
			return ""
	var img := Image.load_from_file(abs_path)
	if img == null:
		_reset_decode_stats("path")
		return ""
	var text := decode_from_image(img)
	last_decode_stats["source"] = "path"
	return text


## Decode text from n×n module matrix (true = dark). Returns "" on failure.
static func decode_from_matrix(mat: Array) -> String:
	if mat.is_empty():
		return ""
	var n: int = mat.size()
	if n < 21:
		return ""
	# Validate square.
	for y in n:
		if not (mat[y] is Array) or (mat[y] as Array).size() != n:
			return ""
	if (n - 17) % 4 != 0:
		return ""
	var ver: int = int((n - 17) / 4)
	if ver < 1 or ver > MAX_VERSION or _size_for_ver(ver) != n:
		return ""
	var locked := _build_function_locked(ver)
	var preferred_mask := _read_format_mask(mat)
	var try_masks: Array = []
	if preferred_mask >= 0 and preferred_mask <= 7:
		try_masks.append(preferred_mask)
	for m in 8:
		if not try_masks.has(m):
			try_masks.append(m)
	for mask in try_masks:
		var unmasked := _apply_mask(mat, locked, int(mask))
		var cws := _modules_to_codewords(unmasked, locked, ver)
		if cws.is_empty():
			continue
		var data_cw := _deinterleave_data(cws, ver)
		if data_cw.is_empty():
			continue
		var text := _parse_byte_payload(data_cw, ver)
		if not text.is_empty():
			return text
	return ""


static func _pixel_luma(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


static func _is_dark_pixel(c: Color, thresh: float = 0.55) -> bool:
	return _pixel_luma(c) < thresh


## Pass 63: mean luma threshold (slightly below mid for light quiet zones).
static func _adaptive_luma_thresh(img: Image) -> float:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return 0.55
	var step := maxi(1, int(mini(w, h) / 64))
	var sum := 0.0
	var n := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			sum += _pixel_luma(img.get_pixel(x, y))
			n += 1
	if n <= 0:
		return 0.55
	var mean := sum / float(n)
	# Midpoint between mean and mid-gray favors high-contrast engine PNGs + photos.
	return clampf((mean + 0.5) * 0.5, 0.28, 0.72)


## Sample module matrix from clean or slightly noisy / mildly skewed QR images.
static func _sample_matrix_from_image(img: Image) -> Array:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var thresh := _adaptive_luma_thresh(img)
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in h:
		for x in w:
			if _is_dark_pixel(img.get_pixel(x, y), thresh):
				if x < min_x:
					min_x = x
				if y < min_y:
					min_y = y
				if x > max_x:
					max_x = x
				if y > max_y:
					max_y = y
	if max_x < min_x or max_y < min_y:
		return []
	var box_w := float(max_x - min_x + 1)
	var box_h := float(max_y - min_y + 1)
	var box_side := maxf(box_w, box_h)
	var best: Array = []
	var best_score := -1.0
	# Subpixel phase + mild shear (Pass 64) for photo-ish trapezoids.
	var phases: Array = [0.5, 0.35, 0.65]
	var shears: Array = [0.0, -0.04, 0.04]
	for ver in range(1, MAX_VERSION + 1):
		var n: int = _size_for_ver(ver)
		for phase in phases:
			var ph: float = float(phase)
			for shear_v in shears:
				var sh: float = float(shear_v)
				# Strategy A: isotropic bbox.
				var px_iso := box_side / float(n)
				var mat_a := _sample_at_xy(img, float(min_x), float(min_y), px_iso, px_iso, n, thresh, ph, sh)
				var sc_a := _matrix_finder_score(mat_a)
				if sc_a > best_score:
					best_score = sc_a
					best = mat_a
				# Strategy A2: anisotropic bbox (mild perspective stretch).
				var px_x := box_w / float(n)
				var px_y := box_h / float(n)
				var mat_a2 := _sample_at_xy(img, float(min_x), float(min_y), px_x, px_y, n, thresh, ph, sh)
				var sc_a2 := _matrix_finder_score(mat_a2)
				if sc_a2 > best_score:
					best_score = sc_a2
					best = mat_a2
				# Strategy B: full image = (n + 2*margin) modules.
				for margin in range(1, 5):
					var total_m := n + margin * 2
					var mx_px := float(w) / float(total_m)
					var my_px := float(h) / float(total_m)
					if mx_px < 0.9 or my_px < 0.9:
						continue
					var mat_b := _sample_at_xy(
						img, float(margin) * mx_px, float(margin) * my_px, mx_px, my_px, n, thresh, ph, sh
					)
					var sc_b := _matrix_finder_score(mat_b)
					if sc_b > best_score:
						best_score = sc_b
						best = mat_b
			if best_score >= 0.92:
				break
		if best_score >= 0.92:
			break
	if best_score < 0.55:
		return []
	return best


## Backward-compatible isotropic sample.
static func _sample_at(
	img: Image,
	ox: float,
	oy: float,
	module_px: float,
	n: int,
	thresh: float = 0.55,
	phase: float = 0.5
) -> Array:
	return _sample_at_xy(img, ox, oy, module_px, module_px, n, thresh, phase, 0.0)


## Pass 64: anisotropic module sampling with optional shear (mx contributes to y, my to x).
static func _sample_at_xy(
	img: Image,
	ox: float,
	oy: float,
	module_px_x: float,
	module_px_y: float,
	n: int,
	thresh: float = 0.55,
	phase: float = 0.5,
	shear: float = 0.0
) -> Array:
	var mat: Array = []
	var w: int = img.get_width()
	var h: int = img.get_height()
	var ph := clampf(phase, 0.2, 0.8)
	var sh := clampf(shear, -0.12, 0.12)
	for my in n:
		var row: Array = []
		for mx in n:
			var u := float(mx) + ph
			var v := float(my) + ph
			var sx := int(ox + u * module_px_x + v * module_px_x * sh)
			var sy := int(oy + v * module_px_y + u * module_px_y * sh)
			sx = clampi(sx, 0, w - 1)
			sy = clampi(sy, 0, h - 1)
			# 3×3 majority for robustness on auto-scaled / mildly soft modules.
			var dark_n := 0
			var tot := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var px2 := clampi(sx + dx, 0, w - 1)
					var py2 := clampi(sy + dy, 0, h - 1)
					tot += 1
					if _is_dark_pixel(img.get_pixel(px2, py2), thresh):
						dark_n += 1
			row.append(dark_n * 2 >= tot)
		mat.append(row)
	return mat


## Score 0–1 based on three finder patterns (7×7 rings).
static func _matrix_finder_score(mat: Array) -> float:
	if mat.is_empty():
		return 0.0
	var n: int = mat.size()
	if n < 21:
		return 0.0
	var s0 := _finder_score_at(mat, 0, 0)
	var s1 := _finder_score_at(mat, n - 7, 0)
	var s2 := _finder_score_at(mat, 0, n - 7)
	return (s0 + s1 + s2) / 3.0


static func _finder_score_at(mat: Array, ox: int, oy: int) -> float:
	var n: int = mat.size()
	var hits := 0
	var total := 0
	for dy in 7:
		for dx in 7:
			var x := ox + dx
			var y := oy + dy
			if x < 0 or y < 0 or x >= n or y >= n:
				return 0.0
			var edge := dx == 0 or dx == 6 or dy == 0 or dy == 6
			var core := dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4
			var expect_dark := edge or core
			# white ring between edge and core
			if not edge and not core:
				expect_dark = false
			total += 1
			if bool(mat[y][x]) == expect_dark:
				hits += 1
	return float(hits) / float(maxi(total, 1))


static func _build_function_locked(ver: int) -> Array:
	var n := _size_for_ver(ver)
	var mat: Array = []
	var locked: Array = []
	for y in n:
		var row: Array = []
		var lrow: Array = []
		for x in n:
			row.append(false)
			lrow.append(false)
		mat.append(row)
		locked.append(lrow)
	_place_finder(mat, locked, 0, 0)
	_place_finder(mat, locked, n - 7, 0)
	_place_finder(mat, locked, 0, n - 7)
	_place_timing(mat, locked)
	_place_alignment(mat, locked, ver)
	_place_dark_module(mat, locked, ver)
	_reserve_format(mat, locked)
	_reserve_version(mat, locked, ver)
	return locked


## Read mask pattern 0–7 from format info; -1 if unreadable.
static func _read_format_mask(mat: Array) -> int:
	var n: int = mat.size()
	var positions_a := [
		[0, 8], [1, 8], [2, 8], [3, 8], [4, 8], [5, 8], [7, 8], [8, 8],
		[8, 7], [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0],
	]
	var bits := 0
	for i in 15:
		var pa: Array = positions_a[i]
		if bool(mat[pa[1]][pa[0]]):
			bits |= 1 << (14 - i)
	bits ^= 0x5412
	var data := (bits >> 10) & 0x1F
	var mask := data & 0x7
	# Verify by re-encoding format for ECC M + mask.
	var expect := _format_bits(0, mask)
	var bits_chk := 0
	for i2 in 15:
		var pa2: Array = positions_a[i2]
		if bool(mat[pa2[1]][pa2[0]]):
			bits_chk |= 1 << (14 - i2)
	if bits_chk == expect:
		return mask
	# Still return extracted mask as preferred candidate.
	return mask


static func _modules_to_codewords(mat: Array, locked: Array, ver: int) -> PackedByteArray:
	var n: int = mat.size()
	var t: Array = _ecc_m_table(ver)
	var total_cw: int = int(t[0])
	var total_bits := total_cw * 8
	var bits: Array = []
	var col := n - 1
	var upward := true
	while col > 0:
		if col == 6:
			col -= 1
		var rows: Array = []
		if upward:
			for r in range(n - 1, -1, -1):
				rows.append(r)
		else:
			for r in n:
				rows.append(r)
		for row in rows:
			for c_off in [0, -1]:
				var x: int = col + c_off
				var y: int = row
				if locked[y][x]:
					continue
				bits.append(1 if bool(mat[y][x]) else 0)
				if bits.size() >= total_bits:
					break
			if bits.size() >= total_bits:
				break
		if bits.size() >= total_bits:
			break
		upward = not upward
		col -= 2
	if bits.size() < total_bits:
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(total_cw)
	for i in total_cw:
		var v := 0
		for j in 8:
			v = (v << 1) | int(bits[i * 8 + j])
		out[i] = v
	return out


## Deinterleave codewords → per-block RS correct → concatenated data codewords.
static func _deinterleave_data(codewords: PackedByteArray, ver: int) -> PackedByteArray:
	var t: Array = _ecc_m_table(ver)
	var ec_per: int = t[1]
	var n1: int = t[2]
	var d1: int = t[3]
	var n2: int = t[4]
	var d2: int = t[5]
	var nb: int = n1 + n2
	if nb <= 0:
		return PackedByteArray()
	var data_blocks: Array = []
	var ec_blocks: Array = []
	var data_lens: Array = []
	for _i in n1:
		var b1 := PackedByteArray()
		b1.resize(d1)
		data_blocks.append(b1)
		var e1 := PackedByteArray()
		e1.resize(ec_per)
		ec_blocks.append(e1)
		data_lens.append(d1)
	for _j in n2:
		var b2 := PackedByteArray()
		b2.resize(d2)
		data_blocks.append(b2)
		var e2 := PackedByteArray()
		e2.resize(ec_per)
		ec_blocks.append(e2)
		data_lens.append(d2)
	var max_d: int = d1 if n2 == 0 else maxi(d1, d2)
	var idx := 0
	for i in max_d:
		for b in nb:
			var bd: PackedByteArray = data_blocks[b]
			if i < bd.size():
				if idx >= codewords.size():
					return PackedByteArray()
				bd[i] = codewords[idx]
				idx += 1
	for i_ec in ec_per:
		for b2i in nb:
			var be: PackedByteArray = ec_blocks[b2i]
			if idx >= codewords.size():
				return PackedByteArray()
			be[i_ec] = codewords[idx]
			idx += 1
	var out := PackedByteArray()
	last_decode_stats["blocks"] = nb
	for bi in nb:
		var dlen: int = int(data_lens[bi])
		var full := PackedByteArray()
		full.resize(dlen + ec_per)
		var db: PackedByteArray = data_blocks[bi]
		var eb: PackedByteArray = ec_blocks[bi]
		for di in dlen:
			full[di] = db[di]
		for ei in ec_per:
			full[dlen + ei] = eb[ei]
		# Pass 63/64: RS correct; fall back to raw data if correction fails.
		var corrected := _rs_correct_block(full, dlen, ec_per)
		if corrected.is_empty():
			last_decode_stats["blocks_raw_fallback"] = int(last_decode_stats.get("blocks_raw_fallback", 0)) + 1
			out.append_array(db)
		else:
			var changed := false
			for ci in mini(dlen, corrected.size()):
				if int(corrected[ci]) != int(db[ci]):
					changed = true
					break
			if changed:
				last_decode_stats["blocks_corrected"] = int(last_decode_stats.get("blocks_corrected", 0)) + 1
			else:
				last_decode_stats["blocks_clean"] = int(last_decode_stats.get("blocks_clean", 0)) + 1
			out.append_array(corrected)
	return out


static func _parse_byte_payload(data_cw: PackedByteArray, ver: int) -> String:
	if data_cw.is_empty():
		return ""
	var bits: Array = []
	for b in data_cw:
		for i in range(7, -1, -1):
			bits.append((int(b) >> i) & 1)
	if bits.size() < 12:
		return ""
	var mode := (int(bits[0]) << 3) | (int(bits[1]) << 2) | (int(bits[2]) << 1) | int(bits[3])
	if mode != 0b0100:
		return ""
	var bi := 4
	var count_bits := 8 if ver <= 9 else 16
	if bi + count_bits > bits.size():
		return ""
	var n := 0
	for _c in count_bits:
		n = (n << 1) | int(bits[bi])
		bi += 1
	if n <= 0 or n > 4096:
		return ""
	if bi + n * 8 > bits.size():
		return ""
	var bytes := PackedByteArray()
	bytes.resize(n)
	for i in n:
		var v := 0
		for _j in 8:
			v = (v << 1) | int(bits[bi])
			bi += 1
		bytes[i] = v
	var text := bytes.get_string_from_utf8()
	# Reject if decode produced replacement-only garbage for non-empty bytes.
	if text.is_empty() and n > 0:
		return ""
	return text
