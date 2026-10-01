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
	# PROMPT: SPICE Netlist + Coordenadas Relativas de Nodos para Dipolos
	# =========================================================================
	var prompt_text = """Eres un sistema experto en análisis de esquemáticos electrónicos y generación de Netlists SPICE (ngspice) para componentes de dos terminales.

Tu tarea es analizar la imagen del circuito, identificar la topología eléctrica real y generar EXCLUSIVAMENTE el bloque de posiciones relativas y el Netlist SPICE.

### REGLAS ESTRICTAS DE EXTRACCIÓN:

1. TOPOLOGÍA, NODOS Y NETLABELS:
   - Todo cable conductor continuo representa UN SOLO NODO ELÉCTRICO.
   - El nodo de referencia o tierra común es SIEMPRE el nodo 0 (N0 / GND).
   - Soporte de NetLabels: Para rieles de alimentación o conexiones por etiqueta (+5V, +3V, -5V, VCC), usa el nombre explícito como nodo o añade una directiva:
     * label <nodo> <nombre_etiqueta> (ej: * label N1 +5V)
   - Numera los demás nodos de forma compacta y continua: 1, 2, 3...

2. POSICIONES RELATIVAS (* positions):
   - Asigna a cada nodo una coordenada entera 2D (x, y) representativa de su ubicación geométrica (x crece hacia la derecha, y crece hacia abajo).
   - Formato exacto en una sola línea tras el encabezado:
     * positions
     N0 x0,y0 ; N1 x1,y1 ; N2 x2,y2 ; ...

3. CONVENCIÓN DE POLARIDAD EN COMPONENTES (ngspice):
   - Fuentes de Tensión: V<id> <nodo_+> <nodo_-> DC <valor>
     * El primer nodo DEBE ser el terminal con el signo (+) o barra larga.
     * El segundo nodo DEBE ser el terminal con el signo (-) o barra corta.
   - Fuentes de Corriente: I<id> <nodo_origen> <nodo_destino> DC <valor>
     * La corriente sale de <nodo_origen> y entra en <nodo_destino> (la flecha del símbolo apunta HACIA <nodo_destino>).
   - Resistores: R<id> <nodoA> <nodoB> <valor> (valor en ohms, ej: 2, 5k, 1MEG).
   - Capacitores e Inductores: C<id> <nodoA> <nodoB> <valor>, L<id> <nodoA> <nodoB> <valor>.

4. SALIDA:
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
