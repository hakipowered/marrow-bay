class_name WebPlatform
## Small helpers for the browser version (Godot Web export served at
## /play/ on the download worker). Everything here is a no-op off the web.

const PLAY_URL := "https://ragoon-city-download.hakipowered.workers.dev/play/"

static func is_web() -> bool:
	return OS.has_feature("web")

## Phones that can buzz: the Android app, and Chrome/Samsung Internet on Android.
static func can_vibrate() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android")

## Link that opens the browser version straight into the join screen.
static func invite_url(code: String) -> String:
	return PLAY_URL + "?join=" + code

## A ?name=value from the page address, or "" (always "" off the web).
static func url_param(name: String) -> String:
	if not is_web():
		return ""
	var v: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get(%s) || ''" % JSON.stringify(name))
	return str(v) if v != null else ""

## Drops ?join=... from the address so a reload doesn't join again.
static func clear_url_params() -> void:
	if is_web():
		JavaScriptBridge.eval("history.replaceState(null, '', location.pathname)")

## Opens the phone's share sheet (WhatsApp, Messages...). False if the
## browser has none; the caller should copy to the clipboard instead.
static func share(text: String) -> bool:
	if not is_web():
		return false
	var ok: Variant = JavaScriptBridge.eval("(navigator.share ? (navigator.share({text: %s}).catch(function(){}), true) : false)" % JSON.stringify(text))
	return ok == true

## Reads the clipboard (the browser may ask once). Off the web this is just
## DisplayServer.clipboard_get(). Awaitable: var t := await WebPlatform.read_clipboard(node)
static func read_clipboard(node: Node) -> String:
	if not is_web():
		return DisplayServer.clipboard_get()
	JavaScriptBridge.eval("window._ragoonClip = null; (navigator.clipboard && navigator.clipboard.readText ? navigator.clipboard.readText().then(function(t){window._ragoonClip = t || ''}, function(){window._ragoonClip = ''}) : (window._ragoonClip = ''))")
	var waited := 0.0
	while waited < 5.0:
		await node.get_tree().process_frame
		waited += node.get_process_delta_time()
		var v: Variant = JavaScriptBridge.eval("window._ragoonClip")
		if v != null:
			return str(v)
	return ""
