#!/usr/bin/env bash
# Cosecha todas las paradas de Tu Bondi (codigo + nombre + coords) recorriendo
# cada ruta de api-examples/01-lines_routes.json con el comando seleccionatraza.
#
# Uso:
#   ./tools/cosechar-paradas.sh [dir-salida]
#
# - Abre UNA sesion PHPSESSID y la reutiliza para todos los POST.
# - Pide con 2 s entre llamadas para no sobrecargar la API municipal.
# - Guarda api-paradas/ruta-<ruta_id>-cli-<cliente>.json por ruta.
# - Al final une todo en paradas-todas.json (codigo, nombre, lat, lon, linea).
#
# OJO: de noche la API suele devolver 408 vacio. Correlo de dia, con servicio.
set -u
OUT="${1:-api-paradas}"
BASE="https://micronauta4.dnsalias.net"
UA="TuBondi-Oma-Harvest/1.0"
SRC="api-examples/01-lines_routes.json"

command -v jq >/dev/null || { echo "falta jq (pacman -S --needed jq)"; exit 1; }
command -v curl >/dev/null || { echo "falta curl"; exit 1; }
[ -f "$SRC" ] || { echo "no existe $SRC (corre desde la raiz del repo)"; exit 1; }
mkdir -p "$OUT"

CJ=$(mktemp)
trap 'rm -f "$CJ"' EXIT
curl -s -c "$CJ" -b "$CJ" -A "$UA" "$BASE/web/urbano/?conf=cbaciudad" -o /dev/null --max-time 15
[ -s "$CJ" ] || { echo "no se pudo abrir sesion"; exit 1; }
echo "sesion OK"

mapfile -t RUTAS < <(jq -r '.lineas[] | "\(.rutas[].ruta_id):\(.cliente):\(.linea_nombre)"' "$SRC" | sort -u)
echo "rutas a consultar: ${#RUTAS[@]}"

ok=0; fail=0
for r in "${RUTAS[@]}"; do
  rid="${r%%:*}"; rest="${r#*:}"; cli="${rest%%:*}"
  dest="$OUT/ruta-$rid-cli-$cli.json"
  [ -s "$dest" ] && { ok=$((ok+1)); continue; }
  if curl -s -c "$CJ" -b "$CJ" -A "$UA" \
      -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
      -H "X-Requested-With: XMLHttpRequest" \
      --data-urlencode "ruta=$rid" --data-urlencode "cliente_id=$cli" \
      --data-urlencode "conf=cbaciudad" \
      "$BASE/usuario/urbano2_cmd.php?cmd=seleccionatraza" \
      --max-time 20 -o "$dest"; then
    if jq -e '.paradas' "$dest" >/dev/null 2>&1; then
      ok=$((ok+1)); echo "OK ruta=$rid cli=$cli"
    else
      fail=$((fail+1)); echo "VACIA ruta=$rid cli=$cli (la API devolvio 408 o nada)"; rm -f "$dest"
    fi
  else
    fail=$((fail+1)); echo "FALLO ruta=$rid cli=$cli"; rm -f "$dest"
  fi
  sleep 2
done

jq -s '[.[].paradas[]] | unique_by(.codigo) | map({code: .codigo, name: .parada_nombre, lat: .lat, lon: .lon, linea: .linea})' "$OUT"/ruta-*.json > "$OUT/paradas-todas.json" 2>/dev/null
echo "listo: ok=$ok fail=$fail"
echo "total paradas unicas: $(jq 'length' "$OUT/paradas-todas.json" 2>/dev/null)"
echo "siguiente: python3 tools/unir-barrios.py con paradas-todas.json para agrupar por barrio"
