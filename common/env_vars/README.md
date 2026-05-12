# Config Generator para Servicios Docker

Este proyecto proporciona una herramienta basada en Docker para generar archivos de configuración (.env, .cnf, .conf, .yml, etc.) a partir de un archivo central de variables y plantillas. Diseñado para entornos con múltiples servicios (Laravel, MySQL, Redis, Traefik, etc.) donde se necesita centralizar la configuración y mantener secretos fuera de las imágenes.
Características

* **Archivo central único**: todas las variables (base y específicas por servicio) se definen en un solo lugar (ej. `project.env-vars`).
* **Sección BASE**: variables comunes que se exportan y pueden ser referenciadas por otras variables mediante `${VAR}`.
* **Soporte para múltiples archivos de entorno**: puedes pasar uno o más archivos .env (como los que usa docker-compose) para que sus variables estén disponibles en el contenedor.
* **Prefijos automáticos**: cada archivo de salida tiene un prefijo derivado de su nombre (ej. `phva.env` → `PHVA_`). Solo las variables con ese prefijo se aplican a dicho archivo.
* **Expansión de variables**: usa envsubst para expandir referencias como `${BASE_URL}` dentro de los valores.
* **Preserva formato**: mantiene comentarios, líneas vacías y el orden original de las plantillas.
* **Variables nuevas**: si una variable con prefijo no existe en la plantilla, se añade al final del archivo con un comentario indicando su origen.
* **Permisos del host**: los archivos generados heredan el UID/GID del usuario que ejecuta el script, permitiendo editarlos sin problemas.

# Estructura de archivos

```
.
├── Dockerfile
├── generate.sh                # Script interno (dentro del contenedor)
├── run-config-generator.sh    # Script para construir y ejecutar el contenedor
├── templates/                  # Carpeta con las plantillas (archivos .example)
│   ├── dashboard.env.example
│   ├── mysql-config.cnf.example
│   ├── redis.conf.example
│   └── traefik_dynamic.yml.example
└── vars/                       # (Opcional) Archivos de variables centrales
    └── project.env-vars        # Archivo central (puede llamarse de otra forma)
```

# Requisitos

* Docker instalado y funcionando.
* Bash.

# Formato del archivo central de variables

El archivo central (ej. `project.env-vars`) debe contener una sección BASE VARIABLES delimitada por marcadores y luego las variables específicas con prefijos.

# Marcadores obligatorios

```text
############################################### BASE VARIABLES #######################################################
... variables base (clave=valor) ...
############################################# END BASE VARIABLES #######################################################
```

# Variables base
Dentro de la sección BASE se definen variables que:

* Se exportan al entorno para que envsubst pueda expandirlas.
* **No se escriben directamente en ningún archivo de salida** (a menos que un servicio las declare explícitamente con su prefijo).
* Tienen prioridad sobre las variables de los archivos `--env-file` en caso de duplicados.

# Variables por servicio
Fuera de la sección BASE, se definen variables con el formato:

```text
PREFIJO_NOMBRE_VARIABLE=valor
```

Donde **PREFIJO** debe coincidir con el nombre del archivo de salida (en mayúsculas, reemplazando caracteres no alfanuméricos por `_`). Por ejemplo:
* Para `phva.env` → prefijo `PHVA_`
* Para `mysql-config.cnf` → prefijo `MYSQL_CONFIG_CNF_` (aunque recomendamos usar nombres simples como mysql.env para evitar prefijos largos)

**Importante**: El valor puede contener referencias a variables base usando ${NOMBRE_VARIABLE_BASE}. Estas referencias se expandirán automáticamente.

# Ejemplo de archivo central (vars/project.env-vars)

```bash
############################################### BASE VARIABLES #######################################################
BASE_URL=http://localhost:3000
APP_PORT_SSL=443
DB_HOST=mysql
DB_USERNAME=root
DB_PASSWORD=toor
TZ=UTC
############################################# END BASE VARIABLES #######################################################

# Variables para el servicio PHVA (archivo phva.env)
PHVA_APP_URL=${BASE_URL}:${APP_PORT_SSL}
PHVA_TIMEZONE=${TZ}
PHVA_VARIABLE_NUEVA="valor nuevo"   # Se añadirá al final de phva.env

# Variables para MySQL (archivo mysql-config.cnf)
MYSQL_HOST=${DB_HOST}
MYSQL_PORT=3306
MYSQL_USER=${DB_USERNAME}
MYSQL_PASSWORD=${DB_PASSWORD}

# Variables para Redis (archivo redis.conf)
REDIS_PORT=6379
REDIS_PASSWORD=${DB_PASSWORD}

# Variables para Traefik (archivo traefik_dynamic.yml)
TRAEFIK_LOG_LEVEL=DEBUG
TRAEFIK_INSECURE=true
```

# Formato de las plantillas
Las plantillas son archivos con extensión `.example` (ej. `phva.env.example`) que contienen la estructura base del archivo de configuración. Pueden incluir comentarios, líneas vacías y asignaciones del tipo `CLAVE=valor`.

**Importante**: Las claves en la plantilla no llevan prefijo. El generador las reemplazará si existe una variable con el prefijo correspondiente en el archivo central.

Ejemplo de `templates/phva.env.example`:

```bash
APP_NAME=Laravel
APP_ENV=local
APP_DEBUG=true
APP_URL=http://localhost

DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=phva
DB_USERNAME=root
DB_PASSWORD=

# ... más variables
```

# Uso del script local
## Pasos

* Clona o crea los archivos del generador (Dockerfile, generate.sh, run-config-generator.sh) en un directorio.
* Prepara tu archivo central de variables (ej. vars/project.env-vars) y tus plantillas en templates/.
* Da permisos de ejecución a los scripts:
```bash
    chmod +x generate.sh run-config-generator.sh
```
* Ejecuta el generador:
**Solo con el archivo central:**
```bash
    ./run-config-generator.sh ./vars/project.env-vars ./generated ./templates
```
**Con uno o más archivos de entorno adicionales (ej. el .env de docker-compose):**
```bash
    ./run-config-generator.sh ./vars/project.env-vars ./generated ./templates ../.env
```
```bash
  ./run-config-generator.sh ./vars/project.env-vars ./generated ./templates ../.env ../.env.production
```
El script:
* Construirá la imagen Docker (si no existe).
* Pasará los archivos `--env-file` al contenedor (tantos como se indiquen).
* Montará los directorios como volúmenes.
* Generará los archivos en el directorio de salida.
* Ajustará los permisos para que coincidan con el usuario del host.

## Salida
En el directorio de salida (./generated) aparecerán los archivos generados, por ejemplo:
* `phva.env`
* `mysql-config.cnf`
* `redis.conf`
* `traefik_dynamic.yml`

## Ejemplo completo
### Archivo central (vars/project.env-vars)
```bash
############################################### BASE VARIABLES #######################################################
BASE_URL=https://miapp.com
APP_PORT_SSL=443
DB_HOST=mysql.prod
DB_USERNAME=admin
DB_PASSWORD=SeCrEtO
TZ=America/Santiago
############################################# END BASE VARIABLES #######################################################

PHVA_APP_URL=${BASE_URL}:${APP_PORT_SSL}
PHVA_TIMEZONE=${TZ}
PHVA_CUSTOM_VAR="Hola mundo"

MYSQL_PORT=3307
MYSQL_USER=${DB_USERNAME}
MYSQL_PASSWORD=${DB_PASSWORD}

REDIS_PORT=6380
```

### Archivo de entorno adicional (../.env)
```bash
# Variables para docker-compose (también disponibles en el generador)
COMPOSE_PROJECT_NAME=gestionasig-local
USER_UID=1000
DB_PORT=3313
REDIS_PORT=6383
```

### Plantilla `templates/phva.env.example`
```bash
APP_NAME=MiApp
APP_ENV=local
APP_DEBUG=true
APP_URL=http://localhost

DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=mi_db
DB_USERNAME=root
DB_PASSWORD=
```

### Comando
```bash
  ./run-config-generator.sh ./vars/project.env-vars ./generated ./templates ../.env
```

### Archivo generado `generated/phva.env`
```bash
APP_NAME=MiApp
APP_ENV=local
APP_DEBUG=true
APP_URL=https://miapp.com:443

DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=mi_db
DB_USERNAME=root
DB_PASSWORD=

# Variables automatically added from ./vars/project.env-vars
CUSTOM_VAR=Hola mundo
TIMEZONE=America/Santiago
```
Observa que `DB_PORT` no se modificó porque no hay `PHVA_DB_PORT` en el archivo central; el valor de la plantilla se mantiene.

### Notas adicionales
* **Prefijos automáticos**: El script deriva el prefijo del nombre del archivo de salida (sin la extensión `.example`). Por ejemplo, `phva.env` → `PHVA_`. Si usas nombres con guiones, estos se convierten en guiones bajos (`mi-servicio.env` → `MI_SERVICIO_`).
* **Variables base**: No se escriben en los archivos finales a menos que un servicio las declare con su prefijo. Solo sirven para expandir referencias.
* **Múltiples archivos de entorno**: Los archivos `--env-file` se cargan en el orden proporcionado. Si una variable aparece en varios, el último valor prevalece. Las variables de la sección BASE del archivo central tienen prioridad sobre todos ellos.
* **Permisos**: El script `run-config-generator.sh` pasa el UID y GID del usuario actual al contenedor, y `generate.sh` ejecuta `chown` para que los archivos generados pertenezcan a ese usuario. Así puedes editarlos/borrarlos sin necesidad de `sudo`.
* **Errores comunes**:
  * Asegúrate de que el archivo central tenga los marcadores exactos (con el mismo número de `#`).
  * Verifica que los prefijos coincidan: `PHVA_` para `phva.env`, `MYSQL_` para `mysql-config.cnf`, etc.
  * Si una variable no se reemplaza, revisa que la clave en la plantilla sea idéntica a la clave sin prefijo.

### Personalización
Si necesitas un prefijo diferente al derivado automáticamente, puedes modificar la función `get_prefix` en `generate.sh` para incluir un mapa de excepciones. Por ejemplo:
```bash
declare -A PREFIX_MAP=(
    ["mysql-config.cnf"]="MYSQL_"
    ["redis.conf"]="REDIS_"
    ["traefik_dynamic.yml"]="TRAEFIK_"
)
if [[ -n "${PREFIX_MAP[$output_name]}" ]]; then
    prefix="${PREFIX_MAP[$output_name]}"
else
    prefix=$(echo "$service_part" | tr '[:lower:]' '[:upper:]')_
fi
```

## Conclusión
Este generador te permite mantener toda la configuración de tu stack en un solo lugar, con separación clara entre variables base y específicas, y generar archivos listos para montar en contenedores.
La integración con los archivos `.env` de docker-compose facilita la gestión de entornos y la reutilización de variables. Es ideal para entornos de desarrollo, staging y producción, especialmente cuando se combina con CI/CD.
