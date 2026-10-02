extends Node2D

enum Estado { INSTRUCOES, JOGANDO, VITORIA, DERROTA }

const TEMPO_TOTAL := 180.0
const VELOCIDADE := 110.0
const VELOCIDADE_GUARDA := 45.0
const ALCANCE_PEGAR := 30.0
const ALCANCE_VISAO := 130.0
const ANGULO_VISAO := 35.0
const TEMPO_ALERTA := 0.6
const USAR_ESCURIDAO := true
const INICIO := Vector2(60, 490)
const ESCALA_PERSONAGEM := 2.0
const FRAMES_POR_SEGUNDO := 8.0
const FUNDO := "res://assets/fundo.jpg"
const TEX_JOGADOR := "res://assets/personagens/jogador.png"
const TEX_GUARDA := "res://assets/personagens/guarda.png"

const TEXTO_INSTRUCOES := "ECOS DA SERRA\n\nGuaramiranga, noite de neblina. Algo aconteceu aqui...\n\nObjetivo: encontre os 4 itens do mapa em até 3 minutos.\nSe um guarda enxergar você, é fim de jogo.\n\nMover: W A S D ou SETAS\nPegar item: E ou ESPAÇO (chegue perto do item)\nReiniciar: Z\n\nPressione ENTER para começar"


class Item:
	var pos: Vector2
	var nome: String
	var texto: String
	var tex: Texture2D
	var altura: float
	var pego := false

	func _init(p: Vector2, n: String, t: String, tx: Texture2D, alt: float) -> void:
		pos = p
		nome = n
		texto = t
		tex = tx
		altura = alt


class Guarda:
	var pos: Vector2
	var a: Vector2
	var b: Vector2
	var destino: Vector2
	var ang := 0.0
	var luz: PointLight2D
	var sprite: Sprite2D

	func _init(p_a: Vector2, p_b: Vector2) -> void:
		a = p_a
		b = p_b
		pos = p_a
		destino = p_b
		ang = (p_b - p_a).angle()


var estado := Estado.INSTRUCOES
var tempo := TEMPO_TOTAL
var alerta := 0.0
var t := 0.0
var nota := ""
var nota_tempo := 0.0

var jogador: CharacterBody2D
var olhando := Vector2.DOWN
var itens: Array = []
var guardas: Array = []
var paredes: Array = []
var neblina: Array = []

var hud: Label
var nota_label: Label
var painel: ColorRect
var texto_painel: Label
var flash: ColorRect
var tex_luz: GradientTexture2D
var tex_fundo: Texture2D
var sprite_jogador: Sprite2D
var dica_label: Label


func _ready() -> void:
	randomize()
	tex_luz = _criar_textura_luz()
	if ResourceLoader.exists(FUNDO):
		tex_fundo = load(FUNDO)
	_criar_acoes()
	_criar_mapa()
	_criar_jogador()
	_criar_ui()
	for i in 10:
		neblina.append(Vector2(randf_range(0, 960), randf_range(40, 500)))
	_resetar()
	_mudar_estado(Estado.INSTRUCOES)

func _adicionar_acao(nome: String, teclas: Array) -> void:
	if not InputMap.has_action(nome):
		InputMap.add_action(nome)
	for k in teclas:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(nome, ev)


func _criar_acoes() -> void:
	_adicionar_acao("esquerda", [KEY_A, KEY_LEFT])
	_adicionar_acao("direita", [KEY_D, KEY_RIGHT])
	_adicionar_acao("cima", [KEY_W, KEY_UP])
	_adicionar_acao("baixo", [KEY_S, KEY_DOWN])
	_adicionar_acao("pegar", [KEY_E, KEY_SPACE])
	_adicionar_acao("resetar", [KEY_Z])
	_adicionar_acao("iniciar", [KEY_ENTER, KEY_KP_ENTER])


func _criar_textura_luz() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func _nova_luz(cor: Color, escala: float, energia: float) -> PointLight2D:
	var luz := PointLight2D.new()
	luz.texture = tex_luz
	luz.color = cor
	luz.texture_scale = escala
	luz.energy = energia
	return luz


func _criar_mapa() -> void:
	paredes = [
		Rect2(0, 0, 960, 24), Rect2(0, 516, 960, 24),
		Rect2(0, 0, 24, 540), Rect2(936, 0, 24, 540),
		Rect2(160, 130, 220, 90), Rect2(450, 125, 180, 120),
		Rect2(200, 280, 140, 60), Rect2(700, 150, 130, 90),
		Rect2(660, 275, 250, 120),
	]
	for r in paredes:
		var corpo := StaticBody2D.new()
		var forma := CollisionShape2D.new()
		var ret := RectangleShape2D.new()
		ret.size = r.size
		forma.shape = ret
		corpo.position = r.position + r.size / 2.0
		corpo.add_child(forma)
		add_child(corpo)

	itens = [
		Item.new(Vector2(140, 250), "Diário molhado",
			"Dia 3. A neblina desceu cedo em Guaramiranga. Ouvi o sino da capela tocar, mas não havia ninguém lá.",
			load("res://assets/itens/diario.png"), 36.0),
		Item.new(Vector2(470, 80), "Lamparina antiga",
			"A lamparina ainda estava morna. Alguém esteve aqui há pouco e deixou pegadas rumo à mata.",
			load("res://assets/itens/lampada.png"), 38.0),
		Item.new(Vector2(860, 260), "Foto rasgada",
			"Uma família posando no cafezal. Um dos rostos foi riscado com carvão.",
			load("res://assets/itens/retrato.png"), 40.0),
		Item.new(Vector2(600, 440), "Chave enferrujada",
			"Gravado na chave: 'Capela'. O que sumiu da serra sempre esteve trancado ali.",
			load("res://assets/itens/chave.png"), 40.0),
	]

	guardas = [
		Guarda.new(Vector2(360, 240), Vector2(800, 240)),
		Guarda.new(Vector2(80, 150), Vector2(80, 330)),
		Guarda.new(Vector2(300, 490), Vector2(850, 490)),
	]
	for g in guardas:
		g.sprite = _novo_sprite(TEX_GUARDA)
		add_child(g.sprite)

	if USAR_ESCURIDAO:
		var mod := CanvasModulate.new()
		mod.color = Color(0.22, 0.26, 0.38)
		add_child(mod)
		for g in guardas:
			g.luz = _nova_luz(Color(1.0, 0.4, 0.4), 0.55, 0.9)
			add_child(g.luz)


func _criar_jogador() -> void:
	jogador = CharacterBody2D.new()
	jogador.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var forma := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 7.0
	forma.shape = circ
	jogador.add_child(forma)
	if USAR_ESCURIDAO:
		jogador.add_child(_nova_luz(Color(1.0, 0.95, 0.75), 1.5, 1.1))
	sprite_jogador = _novo_sprite(TEX_JOGADOR)
	jogador.add_child(sprite_jogador)
	add_child(jogador)


## Spritesheet 4x4: linhas = baixo, direita, cima, esquerda; colunas = frames da caminhada.
func _novo_sprite(caminho: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(caminho)
	s.hframes = 4
	s.vframes = 4
	s.scale = Vector2(ESCALA_PERSONAGEM, ESCALA_PERSONAGEM)
	s.offset = Vector2(0, -6)  # deixa os pés um pouco abaixo do ponto de colisão
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel art nítida
	return s


func _linha_direcao(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return 1 if v.x > 0.0 else 3
	return 0 if v.y > 0.0 else 2


func _novo_label(tam: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l


func _criar_ui() -> void:
	var camada := CanvasLayer.new()
	add_child(camada)

	flash = ColorRect.new()
	flash.color = Color(1, 0, 0, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	hud = _novo_label(20)
	hud.position = Vector2(20, 10)
	camada.add_child(hud)

	dica_label = _novo_label(18)
	dica_label.position = Vector2(0, 405)
	dica_label.size = Vector2(960, 30)
	dica_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	camada.add_child(dica_label)

	nota_label = _novo_label(18)
	nota_label.position = Vector2(40, 440)
	nota_label.size = Vector2(880, 80)
	nota_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	camada.add_child(nota_label)

	painel = ColorRect.new()
	painel.color = Color(0, 0, 0, 0.85)
	painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(painel)
	painel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	texto_painel = _novo_label(22)
	texto_painel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	texto_painel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	texto_painel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	painel.add_child(texto_painel)
	texto_painel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)

func _mudar_estado(novo: Estado) -> void:
	estado = novo
	painel.visible = novo != Estado.JOGANDO
	if novo == Estado.INSTRUCOES:
		texto_painel.text = TEXTO_INSTRUCOES


func _resetar() -> void:
	tempo = TEMPO_TOTAL
	alerta = 0.0
	nota = ""
	nota_tempo = 0.0
	jogador.position = INICIO
	jogador.velocity = Vector2.ZERO
	olhando = Vector2.DOWN
	for i in itens:
		i.pego = false
	for g in guardas:
		g.pos = g.a
		g.destino = g.b
		g.ang = (g.b - g.a).angle()
		if g.luz:
			g.luz.position = g.pos


func _vencer() -> void:
	var historia := ""
	for i in itens:
		historia += "- " + i.texto + "\n"
	texto_painel.text = "VOCÊ ESCAPOU!\n\n" + historia + "\nO sino da capela parou de tocar... por enquanto.\n\nZ para jogar de novo"
	_mudar_estado(Estado.VITORIA)


func _perder(motivo: String) -> void:
	texto_painel.text = "VOCÊ PERDEU\n\n%s\n\nItens: %d/%d\n\nZ para tentar de novo" % [motivo, _coletados(), itens.size()]
	_mudar_estado(Estado.DERROTA)


func _coletados() -> int:
	var n := 0
	for i in itens:
		if i.pego:
			n += 1
	return n

func _process(delta: float) -> void:
	t += delta
	if estado != Estado.INSTRUCOES and Input.is_action_just_pressed("resetar"):
		_resetar()
		_mudar_estado(Estado.JOGANDO)
	elif estado == Estado.INSTRUCOES and Input.is_action_just_pressed("iniciar"):
		_mudar_estado(Estado.JOGANDO)
	elif estado == Estado.JOGANDO:
		_atualizar_jogo(delta)
	_atualizar_neblina(delta)
	_atualizar_sprites()
	_atualizar_hud()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if estado != Estado.JOGANDO:
		return
	var dir := Input.get_vector("esquerda", "direita", "cima", "baixo")
	jogador.velocity = dir * VELOCIDADE
	jogador.move_and_slide()
	if dir != Vector2.ZERO:
		olhando = dir.normalized()


func _atualizar_jogo(delta: float) -> void:
	tempo -= delta
	if tempo <= 0.0:
		tempo = 0.0
		_perder("O tempo acabou. A neblina engoliu a serra.")
		return

	if nota_tempo > 0.0:
		nota_tempo -= delta
		if nota_tempo <= 0.0:
			nota = ""

	var visto := false
	for g in guardas:
		_mover_guarda(g, delta)
		if _guarda_ve_jogador(g):
			visto = true
	if visto:
		alerta += delta / TEMPO_ALERTA
	else:
		alerta = maxf(alerta - delta * 1.5, 0.0)
	if alerta >= 1.0:
		_perder("Um guarda viu você.")
		return

	if Input.is_action_just_pressed("pegar"):
		_tentar_pegar()


func _tentar_pegar() -> void:
	for i in itens:
		if not i.pego and jogador.position.distance_to(i.pos) <= ALCANCE_PEGAR:
			i.pego = true
			nota = "%s\n%s" % [i.nome, i.texto]
			nota_tempo = 7.0
			if _coletados() >= itens.size():
				_vencer()
			return


func _mover_guarda(g: Guarda, delta: float) -> void:
	var para := g.destino - g.pos
	if para.length() < 3.0:
		g.destino = g.a if g.destino == g.b else g.b
		para = g.destino - g.pos
	g.pos += para.normalized() * VELOCIDADE_GUARDA * delta
	g.ang = lerp_angle(g.ang, para.angle(), 4.0 * delta)
	if g.luz:
		g.luz.position = g.pos


func _guarda_ve_jogador(g: Guarda) -> bool:
	var para := jogador.position - g.pos
	var dist := para.length()
	if dist > ALCANCE_VISAO:
		return false
	var frente := Vector2.from_angle(g.ang)
	if absf(frente.angle_to(para)) > deg_to_rad(ANGULO_VISAO):
		return false
	# Paredes bloqueiam a visão.
	var passos := int(dist / 8.0)
	for k in range(1, passos):
		var ponto := g.pos + para * (float(k) / float(passos))
		for r in paredes:
			if r.has_point(ponto):
				return false
	return true


func _atualizar_neblina(delta: float) -> void:
	for i in neblina.size():
		var p: Vector2 = neblina[i]
		p.x += 12.0 * delta
		if p.x > 1060.0:
			p.x = -100.0
		neblina[i] = p


func _atualizar_sprites() -> void:
	var jogando := estado == Estado.JOGANDO
	var coluna := int(t * FRAMES_POR_SEGUNDO) % 4
	var jogador_andando := jogando and jogador.velocity.length() > 1.0
	sprite_jogador.frame = _linha_direcao(olhando) * 4 + (coluna if jogador_andando else 0)
	for g in guardas:
		g.sprite.position = g.pos
		g.sprite.frame = _linha_direcao(Vector2.from_angle(g.ang)) * 4 + (coluna if jogando else 0)


@warning_ignore("integer_division")
func _atualizar_hud() -> void:
	var s := int(ceil(tempo))
	hud.text = "Itens: %d/%d     Tempo: %d:%02d" % [_coletados(), itens.size(), s / 60, s % 60]
	if alerta > 0.0 and estado == Estado.JOGANDO:
		hud.text += "     !! VISTO !!"
	hud.visible = estado != Estado.INSTRUCOES
	nota_label.text = nota
	dica_label.text = ""
	if estado == Estado.JOGANDO:
		for it in itens:
			if not it.pego and jogador.position.distance_to(it.pos) <= ALCANCE_PEGAR:
				dica_label.text = "[E] pegar"
	flash.color = Color(1, 0, 0, clampf(alerta, 0.0, 1.0) * 0.35)


# ---------- Desenho ----------
# Personagens são Sprite2D (desenhados por cima disto). Aqui ficam fundo, mapa, itens e cones.

func _draw() -> void:
	if tex_fundo:
		draw_texture_rect(tex_fundo, Rect2(0, 0, 960, 540), false)
	else:
		draw_rect(Rect2(0, 0, 960, 540), Color(0.2, 0.32, 0.22))

	for i in paredes.size():
		var r: Rect2 = paredes[i]
		if i < 4:
			draw_rect(r, Color(0.003, 0.071, 0.208, 0.941))
		else:
			# "paredes" para impedir passagem (obstaculo)
			draw_rect(r, Color(0.349, 0.251, 0.2, 0.325))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 14)), Color(0.663, 0.29, 0.271, 0.251))  # telhado

	for it in itens:
		if it.pego:
			continue
		draw_circle(it.pos, 22.0 + sin(t * 4.0) * 3.0, Color(1.0, 0.85, 0.3, 0.22))
		draw_arc(it.pos, 26.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.5)
		var tex: Texture2D = it.tex
		var proporcao: float = it.altura / float(tex.get_height())
		var tam := Vector2(tex.get_width(), tex.get_height()) * proporcao
		var flutua := sin(t * 3.0) * 2.0
		draw_texture_rect(tex, Rect2(it.pos - tam / 2.0 + Vector2(0, flutua), tam), false)

	for g in guardas:
		_desenhar_cone(g)

	for p in neblina:
		draw_circle(p, 80.0, Color(0.85, 0.9, 1.0, 0.06))


func _desenhar_cone(g: Guarda) -> void:
	var pts := PackedVector2Array([g.pos])
	var n := 10
	var meio := deg_to_rad(ANGULO_VISAO)
	for k in range(n + 1):
		var a := g.ang - meio + (meio * 2.0) * float(k) / float(n)
		pts.append(g.pos + Vector2.from_angle(a) * ALCANCE_VISAO)
	draw_colored_polygon(pts, Color(1.0, 0.25, 0.25, 0.28))
