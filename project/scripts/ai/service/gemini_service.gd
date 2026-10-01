class_name GeminiService
extends Node

signal request_completed(result_text: String)
signal request_failed(error_message: String)



var http_request: HTTPRequest

func _ready() -> void:
	_ensure_http_request()

func _ensure_http_request() -> void:
	if not http_request:
		http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.request_completed.connect(_on_http_request_completed)

func analyze_image(image_path: String) -> void:
	_ensure_http_request()
	if not FileAccess.file_exists(image_path):
		request_failed.emit("Image file does not exist: " + image_path)
		return

	var bytes = FileAccess.get_file_as_bytes(image_path)
	if bytes.is_empty():
		request_failed.emit("Failed to read image file or file is empty: " + image_path)
		return

	var mime_type = "image/png"
	var lower_path = image_path.to_lower()
	if lower_path.ends_with(".jpg") or lower_path.ends_with(".jpeg"):
		mime_type = "image/jpeg"
	elif lower_path.ends_with(".webp"):
		mime_type = "image/webp"

	var base64_data = Marshalls.raw_to_base64(bytes)

	# =========================================================================
	# PROMPT: SPICE Netlist + Coordenadas Relativas de Nodos para Esquemáticos EDA
	# =========================================================================
	var prompt_text = """Eres un sistema experto en análisis de esquemáticos electrónicos y generación de Netlists SPICE (ngspice) para componentes discretos y circuitos integrados (ICs).

Tu tarea es analizar la imagen del circuito, identificar la topología eléctrica real y generar EXCLUSIVAMENTE el bloque de posiciones relativas y el Netlist SPICE.

### REGLAS ESTRICTAS DE EXTRACCIÓN:

1. TOPOLOGÍA, NODOS Y NETLABELS:
   - Todo cable conductor continuo representa UN SOLO NODO ELÉCTRICO.
   - El nodo de referencia o tierra común es SIEMPRE el nodo 0 (N0 / GND).
   - Soporte de NetLabels: Para rieles de alimentación o etiquetas (+5V, +12V, -12V, VCC, VDD), usa el nombre explícito o añade una directiva:
     * label <nodo> <nombre_etiqueta> (ej: * label N1 +5V)
   - Numera los demás nodos de forma compacta y continua: 1, 2, 3...

2. POSICIONES RELATIVAS (* positions):
   - Asigna a cada nodo una coordenada entera 2D (x, y) representativa de su ubicación geométrica (x crece hacia la derecha, y crece hacia abajo).
   - Formato exacto en una sola línea tras el encabezado:
     * positions
     N0 x0,y0 ; N1 x1,y1 ; N2 x2,y2 ; ...

3. COMPONENTES DISCRETOS DE 2 TERMINALES:
   - Resistores: R<id> <nodoA> <nodoB> <valor> (ej: R1 1 2 10k)
   - Capacitores: C<id> <nodoA> <nodoB> <valor> (ej: C1 2 0 100uF)
   - Inductores: L<id> <nodoA> <nodoB> <valor> (ej: L1 1 2 10mH)
   - Diodos: D<id> <nodo_anodo> <nodo_catodo> <modelo> (ej: D1 1 2 1N4148)
   - Fuentes de Tensión: V<id> <nodo_+> <nodo_-> DC <valor> (ej: V1 1 0 DC 12)
   - Fuentes de Corriente: I<id> <nodo_origen> <nodo_destino> DC <valor>

4. DISPOSITIVOS DISCRETOS MULTI-TERMINAL:
   - Transistor BJT: Q<id> <colector> <base> <emisor> <NPN|PNP|modelo> (ej: Q1 2 1 0 2N2222)
   - Potenciómetro / Trimpot: XPOT<id> <terminal_1> <cursor/wiper> <terminal_2> POT <valor> (ej: XPOT1 1 2 0 POT 10k)
   - Transformador: XTR<id> <pri_+> <pri_-> <sec_+> <sec_-> XFMR <relacion> (ej: XTR1 1 2 3 4 XFMR 1:1)
   - Tiristor SCR: XSCR<id> <anodo> <gate> <catodo> <modelo> (ej: XSCR1 1 2 0 2N5064)
   - TRIAC: XTRIAC<id> <mt2> <gate> <mt1> <modelo> (ej: XTRIAC1 1 2 0 BT136)
   - Amplificador Operacional: XOP<id> <in_+> <in_-> <out> <modelo> (ej: XOP1 2 1 3 LM741)

5. CIRCUITOS INTEGRADOS (ICs) Y SUBCIRCUITOS (X / U):
   - Reguladores Lineales (78xx / LM317): XREG<id> <in> <gnd_adj> <out> <modelo> (ej: XREG1 1 0 2 LM7805)
   - Optoacopladores: XOPTO<id> <anodo> <catodo> <emisor> <colector> <modelo> (ej: XOPTO1 1 2 0 3 PC817)
   - Sensores Analógicos (LM35/TMP36): XSENS<id> <vcc> <gnd> <vout> <modelo> (ej: XSENS1 1 0 2 LM35)
   - Referencia de Tensión (TL431): XREF<id> <catodo> <anodo> <ref> TL431 (ej: XREF1 1 0 2 TL431)
   - Switches Analógicos / Mux (CD4066, CD4051): XSW<id> <in> <out> <ctrl> CD4066
   - ICs Generales: U<id> <pin1> <pin2> ... <pinN> <CHIP_MODEL> (ej: U1 1 2 3 4 5 6 7 8 NE555)

6. SALIDA:
   - Responde únicamente con el código SPICE y comentarios explicativos breves con (*). No incluyas bloques de conversación ni explicaciones fuera del netlist.
"""

	var payload = {
		"contents": [
			{
				"parts": [
					{"text": prompt_text},
					{
						"inline_data": {
							"mime_type": mime_type,
							"data": base64_data
						}
					}
				]
			}
		],
		"generationConfig": {
			"temperature": 0.1
		}
	}

	var json_str = JSON.stringify(payload)
	var headers = PackedStringArray(["Content-Type: application/json"])
	var url = AIConfig.get_api_url()

	var err = http_request.request(url, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		request_failed.emit("Failed to initiate HTTP request to Gemini API (Error code %d)" % err)

func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("HTTP network error occurred (Result code: %d)" % result)
		return

	var body_text = body.get_string_from_utf8()
	if response_code != 200:
		var err_msg = "Gemini API Error (HTTP %d): %s" % [response_code, body_text]
		if response_code == 503:
			err_msg += "\n[Tip: Model '%s' is temporarily overloaded on Google servers. Try switching to 'gemini-3.5-flash-lite' or 'gemini-flash-lite-latest' in the Model selector.]" % AIConfig.get_model()
		request_failed.emit(err_msg)
		return

	var parsed = JSON.parse_string(body_text)
	if not (parsed is Dictionary):
		request_failed.emit("Invalid JSON response from Gemini API")
		return

	var candidates = parsed.get("candidates", [])
	if candidates.is_empty():
		request_failed.emit("Gemini returned no candidates in response")
		return

	var content = candidates[0].get("content", {})
	var parts = content.get("parts", [])
	if parts.is_empty():
		request_failed.emit("Empty content parts in Gemini response")
		return

	var ai_text = parts[0].get("text", "").strip_edges()
	if ai_text.begins_with("```"):
		var first_nl = ai_text.find("\n")
		var last_fence = ai_text.rfind("```")
		if first_nl != -1 and last_fence > first_nl:
			ai_text = ai_text.substr(first_nl + 1, last_fence - first_nl - 1).strip_edges()
	request_completed.emit(ai_text)
