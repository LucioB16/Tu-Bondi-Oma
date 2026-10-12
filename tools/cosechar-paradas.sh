#!/usr/bin/env bash
# Cosecha todas las paradas de Tu Bondi (codigo + nombre + coords) recorriendo
# cada ruta de api-examples/01-lines_routes.json con seleccionatraza.
#
# Uso:
#   ./tools/cosechar-paradas.sh [dir-salida] [rutas-src.json]
#
# Receta anti-408 (hallada 2026-10-12):
# - GET /usuario/urbano.php?conf=cbaciudad con UA de browser (sesion PHPSESSID)
# - Extraer operacion:'NNNNN' del HTML (cambia en cada carga).
# - Registrar fp aleatorio (64 hex) via POST ...?cmd=vista, form fp=<fp>.
# - POSTs con headers de browser (Accept, Origin, Sec-Fetch-*, sin charset en
#   Content-Type) + X-Device-FlakerParam: <fp> + operacion donde corresponda.
# - Reabre sesion ante un 408 y reintenta una vez; 2 s entre llamadas.
set -u
OUT="${1:-api-paradas}"
SRC="${2:-api-examples/01-lines_routes.json}"
BASE="https://micronauta4.dnsalias.net"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36 Edg/154.0.0.0"

command -v jq >/dev/null || { echo "falta jq (pacman -S --needed jq)"; exit 1; }
[ -f "$SRC" ] || { echo "no existe $SRC (corre desde la raiz del repo)"; exit 1; }
mkdir -p "$OUT"

CJ=""; FP=""; OP=""
HDR=()
nueva_sesion() {
  [ -n "$CJ" ] && rm -f "$CJ"
  CJ=$(mktemp)
  curl -s -c "$CJ" -b "$CJ" -A "$UA" "$BASE/usuario/urbano.php?conf=cbaciudad" -o /tmp/ub_page.html --max-time 20 || return 1
  OP=$(grep -a -o -E "operacion:'[0-9]+'" /tmp/ub_page.html | head -1 | grep -a -o -E "[0-9]+")
  [ -n "$OP" ] || return 1
  FP=$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')
  curl -s -c "$CJ" -b "$CJ" -A "$UA" --data-urlencode "fp=$FP" \
    "$BASE/usuario/urbano2_cmd.php?cmd=vista" -o /dev/null --max-time 15 || return 1
  HDR=(-H "Accept: */*" -H "Accept-Language: es-419,es;q=0.9"
       -H "Content-Type: application/x-www-form-urlencoded" -H "Origin: $BASE"
       -H "Referer: $BASE/usuario/urbano.php?conf=cbaciudad"
       -H "Sec-Fetch-Dest: empty" -H "Sec-Fetch-Mode: cors" -H "Sec-Fetch-Site: same-origin"
       -H "X-Device-FlakerParam: $FP")
  return 0
}

trap 'rm -f "$CJ" /tmp/ub_page.html' EXIT
nueva_sesion || { echo "no se pudo abrir sesion"; exit 1; }
echo "sesion OK, operacion=$OP"

mapfile -t RUTAS < <(jq -r '.lineas[] | "\(.rutas[].ruta_id):\(.cliente)"' "$SRC" | sort -u)
echo "rutas a consultar: ${#RUTAS[@]}"

ok=0; fail=0
for r in "${RUTAS[@]}"; do
  rid="${r%%:*}"; cli="${r##*:}"
  dest="$OUT/ruta-$rid-cli-$cli.json"
  if [ -s "$dest" ] && jq -e '.paradas' "$dest" >/dev/null 2>&1; then ok=$((ok+1)); continue; fi
  pedir() {
    curl -s -c "$CJ" -b "$CJ" -A "$UA" "${HDR[@]}" \
      --data "ruta=$rid&cliente_id=$cli&conf=cbaciudad" \
      "$BASE/usuario/urbano2_cmd.php?cmd=seleccionatraza" \
      --max-time 25 -o "$dest"
  }
  pedir
  if ! jq -e '.paradas' "$dest" >/dev/null 2>&1; then
    echo "re-sesionando (ruta=$rid)..."
    nueva_sesion && pedir
  fi
  if jq -e '.paradas' "$dest" >/dev/null 2>&1; then
    ok=$((ok+1)); echo "OK ruta=$rid cli=$cli ($(jq '.paradas | length' "$dest") paradas)"
  else
    fail=$((fail+1)); echo "FALLO ruta=$rid cli=$cli"; rm -f "$dest"
  fi
  sleep 2
done

jq -s '[.[].paradas[]] | unique_by(.codigo) | map({code: .codigo, name: .parada_nombre, lat: .lat, lon: .lon, linea: .linea})' "$OUT"/ruta-*.json > "$OUT/paradas-todas.json" 2>/dev/null
echo "listo: ok=$ok fail=$fail"
echo "total paradas unicas: $(jq 'length' "$OUT/paradas-todas.json" 2>/dev/null)"
echo "siguiente: python3 tools/unir-barrios.py para agrupar por barrio"
