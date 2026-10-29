# ImgMaster 🖼️

**Convierte y organiza imágenes por lotes en Windows, de forma sencilla y desde un menú.**

ImgMaster permite convertir formatos, renombrar, redimensionar, comprimir, encontrar duplicados y girar imágenes sin tener que procesarlas una por una.

## ✨ Funciones

### Conversión de imágenes

Convierte todas las imágenes compatibles de la carpeta seleccionada al formato que elijas. Los resultados se guardan en una carpeta nueva y los archivos originales se conservan.

|       Opción       | Formato | Calidad predeterminada |            Opciones               |
|         ---        |   ---   |          ---           |               ---                 |
| **1. TODO A PNG**  |   PNG   |           —            |        Conversión a PNG           |
| **2. TODO A JPG**  |   JPG   |          92%           | Calidad personalizada de 1 a 100% |
| **3. TODO A WEBP** |   WEBP  |          90%           | Calidad personalizada de 1 a 100% |
| **4. TODO A AVIF** |   AVIF  |          80%           | Calidad personalizada de 1 a 100% |
| **5. TODO A BMP**  |   BMP   |           —            |        Conversión a BMP           |

Al convertir, puedes conservar los nombres originales o numerar las imágenes automáticamente. En JPG, las transparencias se reemplazan por un fondo blanco.

### Herramientas

**6. RENOMBRAR**

Numera las imágenes directamente en su carpeta, sin cambiar su formato ni su contenido. Puedes ordenar los archivos por nombre, fecha de creación o fecha de modificación, y elegir el número inicial. **Esta función sí modifica los nombres de los archivos originales.**

**7. REDIMENSIONAR**

Permite **reducir o ampliar** imágenes indicando el alto, el ancho o ambas dimensiones. Conserva las proporciones para evitar deformaciones y guarda los resultados en una carpeta nueva. La reducción omite las imágenes que no superan los límites elegidos, mientras que la ampliación omite las que ya alcanzan o superan las dimensiones indicadas. **Ampliar una imagen no recupera detalles que no existan en el original.**

**8. COMPRIMIR**

Intenta reducir el peso de las imágenes sin cambiar sus dimensiones. Puedes utilizar la calidad predeterminada o elegir una personalizada para los formatos que la admiten. Solo guarda las copias que realmente ocupan menos espacio.

**9. DETECTAR DUPLICADOS**

Busca imágenes repetidas y muestra los grupos encontrados. Con ImageMagick también puede reconocer imágenes visualmente idénticas aunque tengan formatos o metadatos diferentes. **No elimina, mueve ni modifica archivos.**

**10. GIRAR IMÁGENES**

Permite colocar imágenes en orientación vertical u horizontal mediante giros de 90°, o invertirlas 180°. Para vertical y horizontal, omite las imágenes que ya tienen la orientación solicitada y las cuadradas. Los resultados se guardan como copias.

### Selección de carpeta

**11. SELECCIONAR CARPETA:** abre el explorador de Windows para elegir otra carpeta con imágenes, sin necesidad de mover el programa.

**12. RESTABLECER CARPETA ORIGINAL:** vuelve a la carpeta de trabajo inicial. Esta opción aparece después de seleccionar una carpeta externa.

> **Importante:** si seleccionas una carpeta externa, ImgMaster procesa las imágenes de esa ubicación, pero guarda las carpetas de resultados **junto al archivo `ImgMaster.bat`**. La opción **RENOMBRAR** actúa directamente sobre las imágenes de la carpeta seleccionada.

## 💻 Requisitos

- **Windows 10 u 11**, con Windows PowerShell 5.1.
- **ImageMagick**, necesario para convertir, redimensionar, comprimir y girar imágenes. También permite una detección de duplicados más completa.
- Permisos para leer las imágenes y guardar los resultados.

**RENOMBRAR** y la detección básica de duplicados funcionan incluso sin ImageMagick.

## 📥 Instalación

1. Descarga el proyecto desde **Code → Download ZIP** en GitHub y extrae el archivo.
2. Abre `ImgMaster.bat` con doble clic.
3. Si ImageMagick no está instalado, selecciona **Instalar ImageMagick** en el menú del programa.
4. Cuando termine la instalación, cierra ImgMaster y vuelve a abrirlo.

También puedes instalar ImageMagick manualmente desde su [página oficial para Windows](https://imagemagick.org/script/download.php#windows). Durante la instalación, asegúrate de que `magick.exe` quede disponible en el `PATH` del sistema.

La instalación integrada utiliza **winget** y requiere conexión a Internet. Si ya tienes ImageMagick instalado y disponible, no necesitas instalarlo de nuevo.

## 🚀 Cómo utilizar ImgMaster

1. Coloca `ImgMaster.bat` en la carpeta que contiene tus imágenes y ábrelo, o utiliza la opción **11. SELECCIONAR CARPETA** para elegir otra ubicación.
2. Escribe el número de la función que quieras utilizar y pulsa **Enter**.
3. Elige las opciones que aparezcan en pantalla, como calidad, numeración, dimensiones o giro.
4. Espera a que termine el proceso y consulta la ubicación de los resultados que muestra el programa.

ImgMaster procesa los archivos de la carpeta elegida, **sin buscar imágenes dentro de sus subcarpetas**.

## ⚠️ Información importante

- **Los originales se conservan** al convertir, redimensionar, comprimir o girar imágenes.
- **RENOMBRAR es la excepción:** cambia los nombres de los archivos originales, por lo que conviene comprobar el orden antes de confirmar.
- **DETECTAR DUPLICADOS solo informa:** no borra archivos automáticamente.
- Los resultados se organizan en carpetas con nombres que identifican la operación. Si una carpeta de salida ya existe, ImgMaster crea otra con un sufijo como `(2)` o `(3)` para evitar sobrescribir resultados anteriores.
- El programa reconoce diversos formatos de imagen, pero la compatibilidad concreta de lectura y conversión depende de la instalación de ImageMagick.
- Para archivos GIF animados o imágenes de varias páginas, las operaciones de procesamiento utilizan únicamente el primer fotograma o página.

---

**ImgMaster** — Procesamiento de imágenes por lotes para Windows.
