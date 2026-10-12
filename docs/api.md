# Cadena de la API Tu Bondi (`cbaciudad`)

Base: `https://micronauta4.dnsalias.net`. Todo cuelga de una sesión con cookie
`PHPSESSID` (se obtiene con **GET**, no POST); sin ella los POST devuelven
`408` vacío.

> **Resuelto 2026-10-12**: `operacion` viene **embebido en el HTML** de
> `GET /usuario/urbano.php?conf=cbaciudad` (línea ~3753,
> `operacion:'…'` — cambia en cada carga) y se manda solo en
> `consultacocheporruta`. Además el servidor exige registrar un
> **fingerprint**: `fp.js` calcula SHA-256 de canvas+navigator+ pantalla,
> lo registra con `POST ...?cmd=vista` (form `fp=…`, sin `conf`) y de ahí
> en más cada POST lleva `X-Device-FlakerParam: <fp>`. Con sesión fresca +
> `operacion` de su página + `fp` registrado + headers de browser
> (`Accept`, `Origin`, `Sec-Fetch-*`, `Content-Type` sin charset),
> `consultacocheporruta`, `lineasyrutas`, `seleccionatraza` y
> `proximos_arribos` devuelven `200`. Un `operacion` ajeno o inventado, o
> un `fp` no registrado, dan `408` vacío. `window.flakerParam` nunca se
> asigna en el HTML (solo se usa): cualquier SHA-256 de 64 hex registrado
> sirve. Receta completa y cosechador en `tools/cosechar-paradas.sh`.
>
> Detalle: `proximosarribos.js` (del mismo servidor) llama
> `?cmd=proximos_arribos` con `codigo, conf, show80min, onlygps: true,
> onlygps_array=JSON` (+ `x` / `forzar_llegada_a_parada` opcionales), sin
> `operacion` y con un typo (`heathers` en vez de `headers`, o sea sin
> Content-Type). `nfetch` es solo fetch+timeout; ante `408` la página hace
> `location.reload()`.

## 0. Sesión

```
GET /web/urbano/?conf=cbaciudad   →  Set-Cookie: PHPSESSID=...
```

Guardar el cookiejar y reenviarlo en todo lo demás. Headers que usa el
frontend oficial: `Content-Type: application/x-www-form-urlencoded;
charset=UTF-8`, `X-Requested-With: XMLHttpRequest`,
`Referer: .../web/urbano/?conf=cbaciudad`.

## 1. `cmd=lineasyrutas` — clientes, grupos, líneas

```
POST /usuario/urbano2_cmd.php?cmd=lineasyrutas
form: conf=cbaciudad
```

Respuesta (`api-examples/01-lines_routes.json`, 74 líneas):

```json
{
  "clientes": [{"id": 408, "nombre": "TAMSE"}, {"id": 411, "nombre": "CONIFERAL"},
               {"id": 420, "nombre": "FAM"}, {"id": 421, "nombre": "Si Bus"}],
  "grupos": [{"cliente_id": "408", "grupo_id": "1", "nombre": "CORREDOR A"}, ...],
  "lineas": [{"linea_id": "1", "linea_nombre": "A", "grupo": "1",
              "color": "#0099CB", "cliente": 408, "orden": 1,
              "rutas": [{"ruta_id": "1", "sentido": "I",
                         "ruta_nombre": "MARIANO FRAGUEIRO A PLAZA DE LAS AMERICAS",
                         "longitud": "27"}, ...]}]
}
```

El `cmd` va en la **query**, `conf` en el **form**. De acá salen los dos
números que pide el paso 2: `ruta` = `ruta_id`, `cliente_id` = `cliente`.

## 2. `cmd=seleccionatraza` — todas las paradas de una línea

```
POST /usuario/urbano2_cmd.php?cmd=seleccionatraza
form: ruta=<ruta_id> & cliente_id=<cliente> & conf=cbaciudad
```

Respuesta (`api-examples/03-route_selection.json`, ruta 99 → 79 paradas):

```json
{"traza": [[lon, lat, curso], ...],
 "paradas": [{"codigo": "PB01", "parada_nombre": "SANTA ANA Y PAINE",
              "lat": "-31.411505", "lon": "-64.255723",
              "linea": "42", "sentido": "V", "cliente": 411, ...}],
 "color": ..., "sentido": ..., "notificacion": ...}
```

**Este es el paso que llena el catálogo del widget**: iterando todas las
rutas del paso 1 se obtiene cada parada con `codigo` (lo que el widget
consulta), nombre y coordenadas. Ver `tools/cosechar-paradas.sh`.

## 3. `cmd=consultacocheporruta` — coches de una ruta

```
POST /usuario/urbano2_cmd.php?cmd=consultacocheporruta
form: ruta=<ruta_id> & coche=0 & cliente=<cliente>
      & [parada_seleccionada=<codigo>] & conf=cbaciudad [& operacion=<nro largo>]
```

Respuesta (`api-examples/04-*.json`, `05-*.json`):

```json
{"coches": [{"coche": "279", "linea": "42", "ruta": "99",
             "itinerario_codigo": "PB07", "lat": -31.41, "lon": -64.25,
             "servicio": "426703", "demora_minutos": 13.78, ...}],
 "notificacion": "", "error": null}
```

Notas:

- `itinerario_codigo` son **códigos de parada** (ej. `PB07`, `TR59`,
  `CE53`) — sirven para verificación cruzada del catálogo.
- `operacion` (número largo, ¿epoch/id de servicio?) lo manda el frontend
  web; el cliente .NET (`TuBondiClient.QueryVehiclesByRouteAsync`) funciona
  sin él con `ruta, coche=0, cliente, conf` + `parada_seleccionada`
  opcional. Para el catálogo no hace falta.
- Con `parada_seleccionada` la respuesta trae el cálculo contra esa parada
  (`05-vehicles_by_route_with_stop.json`).

## 4. `cmd=proximos_arribos` — arribos de una parada (lo que usa el widget)

```
POST /usuario/urbano2_cmd.php            (sin cmd en la query)
form: conf & codigo=<parada> & show80min=true|false
      & onlygps_array={} & cmd=proximos_arribos
```

Respuesta (`api-examples/06-arrivals.json`):

```json
{"parada": {"codigo": "A911", "descripcion": "AV. DUARTE QUIROS 1717-1728"},
 "proximos_arribos": [{"linea": "42", "demora": "14min", "proximo": "11min",
   "distancia": 10.55, "color": "#ff9500", "cliente_nombre": "CONIFERAL",
   "ruta_descripcion": "PARQUE REPUBLICA A PATRICIOS",
   "notificacion": "Se anula paradas en ...", ...}]}
```

El widget normaliza esto con `jq` (ver `widget.owl`): `eta` = 0 si el texto
contiene "arrib"/"llega", si no los dígitos.

## Resumen para llenar el setup

```
lineasyrutas → (ruta_id, cliente) → seleccionatraza → paradas(codigo, nombre, lat/lon)
                                                         ↓ cruce con polígonos
                                              catálogo por barrio (hoodCatalog)
consultacocheporruta → itinerario_codigo → verificación cruzada de códigos
proximos_arribos(codigo) → lo que muestra el tile
```
