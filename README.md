# Tu Bondi · Oma (widget)

Widget de home-screen para [omalauncher](https://github.com/SimonSchubert/omarchy-widgets) que muestra los próximos arribos de **Tu Bondi** en Córdoba. Es la versión widget de [Tu-Bondi-Tracker](https://github.com/LucioB16/Tu-Bondi-Tracker): misma parada, mismas líneas, mismo flujo contra la API municipal, pero sin backend .NET — el widget consulta directo y vive en el teléfono.

Por defecto: parada **A911** (AV. DUARTE QUIROS 1717-1728), líneas **40, 42 y 71**.

## ¿Qué es este proyecto?

Un widget OWL de un solo archivo (`widget.owl`, ~7 KB) que replica el tablero LED del repo original:

- Fila superior: parada + reloj (se actualiza cada 30 s).
- Fila central: próximos 2 arribos en el tile (hasta 6 en la vista completa), ordenados por ETA, con línea, destino, distancia, empresa y minutos restantes. Si hay `notificacion`, muestra fila de alerta amarilla.
- Fila inferior: “actualizado HH:mm”.
- Vista completa (`screen`, toca el tile): los 6 arribos con detalle, avisos, reloj HH:mm:ss y configuración de parada/líneas con `Input` (persisten entre reinicios).
- Sin servicio (de noche o API caída): muestra “offline / sin arribos” y botón de reintentar, igual que el manejo de errores del backend original.

## ¿Cómo funciona (de punta a punta)?

```
┌──────────┐  cada 60 s   ┌───────────────────┐  POST form   ┌──────────────┐
│ widget   │ ───────────▶ │ bash (curl + jq)  │ ───────────▶ │ Tu Bondi     │
│ (OWL)    │  cmd + status│ sesion PHPSESSID  │  urb_cmd.php │ (cbaciudad)  │
└──────────┘              └───────────────────┘              └──────────────┘
      ▲                            │ normaliza a JSON                │
      │                            ▼                                 │
      │                   {stop, desc, arrivals[], updated, error}     │
      │                   filtra por lineas, ordena por ETA           │
      └────────────────── tile 3x3 + screen ─────────────────────────┘
```

1. El `cmd` abre sesión con `GET /web/urbano/?conf=cbaciudad` (guarda `PHPSESSID` en un cookiejar temporal) y luego hace `POST /usuario/urbano2_cmd.php` con `conf=cbaciudad`, `codigo=<parada>`, `show80min=true`, `onlygps_array={}`, `cmd=proximos_arribos` — los mismos parámetros que `TuBondiClient.GetArrivalsAsync` en el repo original.
2. `jq` normaliza `proximos_arribos` a `{line, dest, route, etaTxt, eta, dist, color, op, notif}`. `eta` se extrae igual que `TuBondiGateway.ParseEta`: “arribando/llega” → 0, si no los dígitos (`11min` → 11).
3. El widget filtra por las líneas configuradas, ordena por `eta` y toma 6 (2 en el tile).
4. Si el POST falla o no es JSON, el script imprime `{"error":"offline",...}` y el tile ofrece reintentar, como el `fetchLoop` de `board.js`.

## Requisitos previos

- Un teléfono con omalauncher + Linux opcional (este widget necesita Linux porque usa `cmd`).
- En Arch: `curl` y `jq` (declarados en `requires { pacman: ["curl", "jq"] }`).
- Acceso a Internet a `https://micronauta4.dnsalias.net`.

## Instalación y ejecución local

1. Copiá el widget a tu home-screen:
   ```
   cp widget.owl ~/.config/omalauncher/widgets/30-tu-bondi.owl
   ```
   Aparece en la home en ~1 segundo.
2. Instalá lo que declara:
   ```
   pacman -S --needed curl jq
   ```
3. Verificá que compila y mirá el preview con datos vivos:
   ```
   owl-check 30-tu-bondi.owl
   ```
   Imprime los errores y la ruta del PNG del tile (y de su screen, porque tiene una). Abrilos para ver si el texto entra.

## Configuración

Sin editar el archivo: abrí la vista completa (tocá el tile) y cambiá el código de parada y las líneas en los campos (se guardan con `persist`):

- Parada: `A911`
- Líneas: `40,42,71`

Equivalente a las variables del repo original (`Tracker__StopCode`, `Tracker__Lines`). El intervalo de refresco es 60 s (el original usa 25 s con caché de 12 s; en el widget se espacia para no sobrecargar la API municipal) y el reloj va cada 30 s.

## Uso del tablero

- Tile: próximos 2 arribos + aviso + hora de actualización. Tocarlo abre la vista completa.
- Screen: los 6 arribos con empresa, distancia y avisos; hora actual y de actualización; campos de parada/líneas; botones a Tu Bondi web y al repo original.
- Si la API devuelve `notificacion`, se muestra como fila amarilla (igual que la fila verde intermitente del LED original).

## Pruebas

```
owl-check 30-tu-bondi.owl
```

Criterios (igual que los xUnit del repo original, adaptados):

- El `jq` mapea `api-examples/06-arrivals.json` a arribos con `eta` 11/21/49.
- Filtra por líneas y ordena por ETA con tope de 6.
- Sin red o con `408` (de noche la API corta) muestra “offline” y conserva el mensaje, no rompe el tile.
- `curl` y `jq` están en `requires` y el `.errors/` no advierte programas sin declarar.

Para probar el layout con datos aunque la API esté caída, este repo trae `api-examples/06-arrivals.json` (el mismo ejemplo del repo original).

## Buenas prácticas y límites

- **Etiqueta**: el script usa `User-Agent: TuBondi-Tracker-Widget/1.0`.
- **Caching**: refresco cada 60 s (más espaciado que los 10–15 s del backend).
- **Rate limiting**: un solo comando a la vez; si falla, espera al próximo intervalo o toca reintentar.
- **Privacidad**: la cookie `PHPSESSID` vive en un `mktemp` que se borra en cada corrida. Nunca se expone.
- **Seguridad**: siempre HTTPS contra `micronauta4.dnsalias.net`.

## Capturas y demo

- `preview.png`: PNG del tile generado por `owl-check` (ver última corrida).
- Original: `https://github.com/LucioB16/Tu-Bondi-Tracker` y su `docs/led-board.svg`.

## Preguntas frecuentes

**No se muestra nada / dice offline**

- De noche la API municipal devuelve `408` vacío (verificado 22:30 ART). Esperá al horario de servicio y tocá reintentar.
- Verificá con `curl` que `GET /web/urbano/?conf=cbaciudad` devuelva 200.

**¿Cómo agrego otra línea o parada?**

- En la vista completa cambiá los campos, o editá los `state` por defecto en `widget.owl`.

**¿Problemas con la cookie / sesión?**

- El script reabre la sesión en cada corrida (no la reutiliza entre intervalos), así que una `PHPSESSID` vencida se renueva sola.

## Créditos y referencias

- Repo original: https://github.com/LucioB16/Tu-Bondi-Tracker
- Fuente de datos Tu Bondi: https://micronauta4.dnsalias.net/web/urbano/?conf=cbaciudad
- Lenguaje de widgets OWL: ver `README.md` de `~/.config/omalauncher/widgets`

## Licencia

GPL-3.0-only. Ver `LICENSE`.
