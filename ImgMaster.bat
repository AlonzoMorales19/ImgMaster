@echo off
setlocal EnableExtensions DisableDelayedExpansion
title ImgMaster
rem ============================================================
rem ImgMaster - version sin historial y con reintentos (BAT + PowerShell)
rem Requiere Windows PowerShell 5.1. ImageMagick para convertir.
rem Mantiene la carpeta de trabajo actual, igual que el original.
rem ============================================================
set "IMGMASTER_SELF=%~f0"
set "IMGMASTER_FOLDER=%~dp0"
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: Windows PowerShell no esta disponible.
    pause
    exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $raw=[IO.File]::ReadAllText($env:IMGMASTER_SELF); $tag='#=== IMGMASTER_POWERSHELL ==='; $at=$raw.LastIndexOf($tag,[StringComparison]::Ordinal); if($at -lt 0){throw 'No se encontro el codigo interno de ImgMaster.'}; $script=$raw.Substring($at+$tag.Length); Invoke-Expression $script } catch { [Console]::Error.WriteLine('ERROR: '+$_.Exception.Message); exit 1 }"
set "IM_EXIT=%errorlevel%"
if not "%IM_EXIT%"=="0" (
    echo.
    echo ImgMaster finalizo con un error.
    pause
)
exit /b %IM_EXIT%
#=== IMGMASTER_POWERSHELL ===
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Numerics -ErrorAction Stop
# Trabajar con las imagenes junto al BAT al abrirlo con doble clic.
# Si se ejecuta desde una consola en una carpeta con imagenes, respetar esa carpeta.
$script:WorkDir = (Get-Location).ProviderPath
$script:BatDir = [IO.Path]::GetFullPath($env:IMGMASTER_FOLDER)
$script:KnownImageExtensions = @('.jpg','.jpeg','.png','.webp','.bmp','.gif','.tif','.tiff','.heic','.heif','.avif','.jfif','.ico','.svg','.dds','.tga')
$cwdImages = @(Get-ChildItem -LiteralPath $script:WorkDir -File -ErrorAction SilentlyContinue | Where-Object { $script:KnownImageExtensions -contains $_.Extension.ToLowerInvariant() })
if ($cwdImages.Count -eq 0 -and [IO.Directory]::Exists($script:BatDir)) {
    $script:WorkDir = $script:BatDir
}
# La carpeta inicial conserva el comportamiento original. La seleccion externa
# es opcional y solo permanece activa durante esta ejecucion.
$script:InitialWorkDir = $script:WorkDir
$script:ExternalFolderSelected = $false
function Get-ResultsRoot {
    if ($script:ExternalFolderSelected) { return $script:BatDir }
    return $script:WorkDir
}
# Selector moderno de carpetas de Windows (IFileOpenDialog + FOS_PICKFOLDERS).
# Se carga solo cuando el usuario elige la opcion 11.
function Select-ImagesFolder {
    try {
        if (-not ('ImgMasterModernFolderPicker' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMFolderDialog {
    [PreserveSig] int Show(IntPtr owner);
    void SetFileTypes(uint count, IntPtr filters);
    void SetFileTypeIndex(uint index);
    void GetFileTypeIndex(out uint index);
    void Advise(IntPtr events, out uint cookie);
    void Unadvise(uint cookie);
    void SetOptions(uint options);
    void GetOptions(out uint options);
    void SetDefaultFolder(IMShellItem folder);
    void SetFolder(IMShellItem folder);
    void GetFolder(out IMShellItem folder);
    void GetCurrentSelection(out IMShellItem item);
    void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
    void GetFileName(out IntPtr name);
    void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
    void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string text);
    void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
    void GetResult(out IMShellItem item);
    void AddPlace(IMShellItem item, int location);
    void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string extension);
    void Close(int error);
    void SetClientGuid(ref Guid guid);
    void ClearClientData();
    void SetFilter(IntPtr filter);
    void GetResults(out IntPtr items);
    void GetSelectedItems(out IntPtr items);
}
[ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMShellItem {
    void BindToHandler(IntPtr bindContext, ref Guid bhid, ref Guid riid, out IntPtr result);
    void GetParent(out IMShellItem parent);
    void GetDisplayName(uint displayNameType, out IntPtr name);
    void GetAttributes(uint mask, out uint attributes);
    void Compare(IMShellItem other, uint hint, out int order);
}
public static class ImgMasterModernFolderPicker {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode, PreserveSig=true)]
    private static extern int SHCreateItemFromParsingName(
        [MarshalAs(UnmanagedType.LPWStr)] string path, IntPtr bindContext,
        ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IMShellItem item);

    public static string Pick(string initialPath) {
        object instance = Activator.CreateInstance(Type.GetTypeFromCLSID(
            new Guid("dc1c5a9c-e88a-4dde-a5a1-60f82a20aef7")));
        IMFolderDialog dialog = (IMFolderDialog)instance;
        IMShellItem initial = null;
        IMShellItem selected = null;
        try {
            uint options;
            dialog.GetOptions(out options);
            dialog.SetOptions(options | 0x20u | 0x800u); // PICKFOLDERS + FORCEFILESYSTEM
            dialog.SetTitle("Seleccionar carpeta de imagenes");
            dialog.SetOkButtonLabel("Seleccionar carpeta");
            if (!String.IsNullOrEmpty(initialPath) && System.IO.Directory.Exists(initialPath)) {
                Guid iid = new Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe");
                if (SHCreateItemFromParsingName(initialPath, IntPtr.Zero, ref iid, out initial) == 0)
                    dialog.SetFolder(initial);
            }
            int hr = dialog.Show(IntPtr.Zero);
            if (hr == unchecked((int)0x800704C7)) return null; // cancelado
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
            dialog.GetResult(out selected);
            IntPtr pointer;
            selected.GetDisplayName(0x80058000u, out pointer); // SIGDN_FILESYSPATH
            try { return Marshal.PtrToStringUni(pointer); }
            finally { Marshal.FreeCoTaskMem(pointer); }
        } finally {
            if (selected != null) Marshal.ReleaseComObject(selected);
            if (initial != null) Marshal.ReleaseComObject(initial);
            Marshal.ReleaseComObject(instance);
        }
    }
}
'@
        }
        $selected = [ImgMasterModernFolderPicker]::Pick($script:WorkDir)
        if ([string]::IsNullOrWhiteSpace($selected)) { return }
        $selected = [IO.Path]::GetFullPath($selected)
        if (-not [IO.Directory]::Exists($selected)) {
            throw 'La carpeta seleccionada ya no existe.'
        }
        $folderInfo = [IO.DirectoryInfo]::new($selected)
        if (($folderInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Por seguridad, selecciona una carpeta normal y no un enlace.'
        }
        $enumerator = [IO.Directory]::EnumerateFileSystemEntries($selected).GetEnumerator()
        try { [void]$enumerator.MoveNext() } finally { $enumerator.Dispose() }
        $script:WorkDir = $selected
        $script:ExternalFolderSelected = $true
    } catch {
        Write-Host ('ERROR al seleccionar carpeta: '+$_.Exception.Message) -ForegroundColor Red
        Wait-User
    }
}
function Restore-InitialFolder {
    $script:WorkDir = $script:InitialWorkDir
    $script:ExternalFolderSelected = $false
}
$script:Extensions = @('.jpg','.jpeg','.png','.webp','.bmp','.gif','.tif','.tiff',
    '.heic','.heif','.avif','.jfif','.ico','.svg','.dds','.tga')
$script:TargetFormats = @('png','jpg','webp','avif','bmp')
$script:HasMagick = $false

# Reutiliza el orden natural del ImgMaster original, incluida la prioridad
# del archivo base frente a variantes como foto (1) o foto_copia.
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
public sealed class ImgMasterNaturalComparer : IComparer<FileInfo> {
    [DllImport("shlwapi.dll", CharSet=CharSet.Unicode)]
    private static extern int StrCmpLogicalW(string a, string b);
    private static string Stem(FileInfo f) {
        return Path.GetFileNameWithoutExtension(f.Name).TrimEnd();
    }
    private static bool IsDelimitedVariant(string b, string c) {
        if (c.Length <= b.Length || !c.StartsWith(b, StringComparison.OrdinalIgnoreCase)) return false;
        return !char.IsLetterOrDigit(c[b.Length]);
    }
    public int Compare(FileInfo x, FileInfo y) {
        string a=Stem(x), b=Stem(y);
        bool bv=IsDelimitedVariant(a,b), av=IsDelimitedVariant(b,a);
        if (bv && !av) return -1;
        if (av && !bv) return 1;
        int r=StrCmpLogicalW(a,b);
        if (r!=0) return r;
        r=StrCmpLogicalW(x.Name,y.Name);
        if (r!=0) return r;
        return StringComparer.OrdinalIgnoreCase.Compare(x.FullName,y.FullName);
    }
}
'@

function Header([string]$title) {
    Clear-Host
    Write-Host '==========================================' -ForegroundColor DarkGray
    Write-Host ('               ' + $title) -ForegroundColor Yellow
    Write-Host '==========================================' -ForegroundColor DarkGray
    Write-Host ''
}
function Wait-User { [void](Read-Host 'Presiona Enter para continuar') }
function Ask([string]$prompt, [string[]]$allowed) {
    while ($true) {
        $v = (Read-Host $prompt).Trim()
        if ($allowed -contains $v) { return $v }
        Write-Host 'Opcion no valida.' -ForegroundColor Yellow
    }
}
function Image-Files([string]$order) {
    $files = @(Get-ChildItem -LiteralPath $script:WorkDir -File |
        Where-Object { $script:Extensions -contains $_.Extension.ToLowerInvariant() -and
            -not $_.Name.StartsWith('__ImgMaster_') -and
            -not $_.Name.StartsWith('.ImgMaster_') })
    if ($order -eq '2') { return @($files | Sort-Object CreationTime, Name) }
    if ($order -eq '3') { return @($files | Sort-Object LastWriteTime, Name) }
    $list = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    foreach ($f in $files) { [void]$list.Add($f) }
    $list.Sort((New-Object ImgMasterNaturalComparer))
    return $list.ToArray()
}
function Ask-Order {
    Header 'ORDEN PARA RENOMBRAR'
    Write-Host '1. Nombre actual (orden natural)'
    Write-Host '2. Fecha de creacion'
    Write-Host '3. Fecha de modificacion'
    Write-Host '4. Volver'
    Write-Host ''
    return (Ask 'Seleccione una opcion' @('1','2','3','4'))
}
function Ask-Names {
    while ($true) {
        Header 'FORMATO DE NOMBRES'
        Write-Host '1. Numeracion predeterminada (01, 02, 03... 99, 100, 101...)'
        Write-Host '2. Personalizar numero inicial'
        Write-Host '3. Volver'
        Write-Host ''
        $choice = Ask 'Seleccione una opcion' @('1','2','3')
        if ($choice -eq '3') { return $null }
        $start = '1'
        if ($choice -eq '2') {
            while ($true) {
                $n = (Read-Host 'Numero inicial (0 o mayor)').Trim()
                if ($n -match '^\d+$' -and $n.Length -le 190) {
                    $start = $n.TrimStart('0')
                    if ($start -eq '') { $start = '0' }
                    break
                }
                Write-Host 'Numero no valido. Introduce un entero positivo o cero.' -ForegroundColor Yellow
            }
        }
        return [pscustomobject]@{ Prefix=''; Start=$start; Width=2 }
    }
}
function Number-Name($cfg, [int]$index) {
    # Dos digitos como minimo, sin un maximo fijo de digitos.
    # BigInteger evita el limite numerico anterior de 999999999.
    $value = [System.Numerics.BigInteger]::Parse([string]$cfg.Start) +
        [System.Numerics.BigInteger]$index
    $digits = $value.ToString([Globalization.CultureInfo]::InvariantCulture)
    $name = [string]$cfg.Prefix + $digits.PadLeft([int]$cfg.Width, '0')
    # Windows limita la longitud de cada componente de ruta.
    if ($name.Length -gt 200) { throw 'El nombre generado es demasiado largo para Windows.' }
    return $name
}
function Ask-Quality([string]$format) {
    if ($format -notin @('jpg','webp','avif')) { return $null }
    $default = @{jpg=92;webp=90;avif=80}[$format]
    while ($true) {
        Header 'CALIDAD DE CONVERSION'
        Write-Host ('Formato: ' + $format.ToUpperInvariant())
        Write-Host ('1. Predeterminada (' + $default + ')')
        Write-Host '2. Personalizada (1-100)'
        Write-Host '3. Volver'
        Write-Host ''
        $v = Ask 'Seleccione una opcion' @('1','2','3')
        if ($v -eq '3') { return -1 }
        if ($v -eq '1') { return $default }
        while ($true) {
            $n = (Read-Host 'Calidad (1-100)').Trim()
            if ($n -match '^\d{1,3}$' -and [int]$n -ge 1 -and [int]$n -le 100) { return [int]$n }
            Write-Host 'Introduce un numero entre 1 y 100.'
        }
    }
}
# Primera conversion: carpeta con el mismo nombre que la carpeta raiz.
# Si ya existe: "Nombre - FORMATO" y luego "Nombre - FORMATO (2)", etc.
# Se consideran tambien archivos, carpetas ocultas y enlaces, para no
# reutilizar ni sobrescribir una ruta de una conversion anterior.
function Get-OutputDir([string]$format,$quality) {
    if ($script:TargetFormats -notcontains $format) {
        throw ('Formato de salida no admitido: '+$format)
    }
    $root = Get-ResultsRoot
    $leaf = Split-Path -Path $script:WorkDir -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf='Imagenes' }
    $used = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($root)) {
        [void]$used.Add([IO.Path]::GetFileName($path))
    }
    # Mantener el nombre historico para formatos sin selector de calidad.
    # Para formatos con calidad, el nombre siempre identifica la configuracion.
    if ($null -eq $quality -and -not $used.Contains($leaf)) {
        return (Join-Path $root $leaf)
    }
    $baseName = $leaf + ' - ' + $format.ToUpperInvariant()
    if ($null -ne $quality) { $baseName += ' - CALIDAD ' + [string]$quality + '%' }
    if (-not $used.Contains($baseName)) {
        return (Join-Path $root $baseName)
    }
    for ($i=2; $i -le 1000000; $i++) {
        $name = $baseName + ' (' + $i + ')'
        if (-not $used.Contains($name)) {
            return (Join-Path $root $name)
        }
    }
    throw 'No se encontro un nombre libre para la carpeta de salida.'
}
function Ensure-OutputDir([string]$dir) {
    if ([IO.File]::Exists($dir)) {
        throw ('La ruta de salida ya existe como archivo: '+$dir)
    }
    if (-not [IO.Directory]::Exists($dir)) {
        # Crear por ruta literal: los corchetes en nombres de carpetas
        # no deben interpretarse como comodines de PowerShell.
        [void][IO.Directory]::CreateDirectory($dir)
    }
    $folder = Get-Item -LiteralPath $dir -Force -ErrorAction Stop
    if (-not $folder.PSIsContainer -or
        ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ('Carpeta de salida no segura o es un enlace: '+$dir)
    }
}
function Path-Key([string]$p) { return $p.ToUpperInvariant() }
function Get-Free-Output([string]$dir,[string]$stem,[string]$ext,$reserved) {
    $n=1
    while ($true) {
        $name = if ($n -eq 1) { $stem + '.' + $ext } else { $stem + '_' + $n + '.' + $ext }
        $path = Join-Path $dir $name
        if (-not [IO.File]::Exists($path) -and -not [IO.Directory]::Exists($path) -and
            -not $reserved.Contains((Path-Key $path))) {
            [void]$reserved.Add((Path-Key $path)); return $path
        }
        $n++
        if ($n -gt 1000000) { throw 'No hay nombres de salida disponibles.' }
    }
}
function Make-Convert-Plan($files,[string]$format,$names,$quality) {
    # Elegir y reservar UNA carpeta para toda la conversion.
    # No volver a calcularla al ejecutar: de lo contrario, como ahora
    # ya existe, se elegiria equivocadamente otra carpeta distinta.
    $dir = Get-OutputDir $format $quality
    $folderName = Split-Path -Path $dir -Leaf
    $root = Get-ResultsRoot
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($root)) {
        if ([StringComparer]::OrdinalIgnoreCase.Equals(
            [IO.Path]::GetFileName($path),$folderName)) {
            throw ('La carpeta de salida fue ocupada por otro proceso: '+$dir)
        }
    }
    Ensure-OutputDir $dir
    $reserved = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $plan = @()
    $i = 0
    foreach ($f in $files) {
        $stem = if ($null -eq $names) { $f.BaseName } else { Number-Name $names $i }
        $dest = Get-Free-Output $dir $stem $format $reserved
        $plan += [pscustomobject]@{ Source=$f.FullName; Destination=$dest }
        $i++
    }
    return $plan
}
# Los argumentos se construyen como elementos separados. No unir la ruta
# con '-auto-orient' ni con las otras opciones: eso impedia leer las PNG.
# La misma llamada se usa para TODOS los formatos y su comprobacion.
function Invoke-Magick([string[]]$arguments) {
    # PowerShell 5.1 convierte stderr nativo en errores de PowerShell.
    # Capturarlo sin que ErrorActionPreference='Stop' aborte el lote.
    $ErrorActionPreference = 'Continue'
    try {
        $messages = & magick.exe @arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    } catch {
        return [pscustomobject]@{ ExitCode=1; Message=$_.Exception.Message }
    }
    return [pscustomobject]@{ ExitCode=$code; Message=$messages.Trim() }
}
function Check-Format([string]$format) {
    $probe = Join-Path ([IO.Path]::GetTempPath()) ('ImgMaster_probe_'+[guid]::NewGuid().ToString('N')+'.'+$format)
    try {
        $arguments = @('-size','1x1','xc:white',$probe)
        $result = Invoke-Magick $arguments
        if ($result.ExitCode -ne 0 -or -not [IO.File]::Exists($probe) -or
            (Get-Item -LiteralPath $probe).Length -eq 0) { return $false }
        # Comprobar el formato REAL, no solo la extension: algunas
        # instalaciones generan PNG cuando falta el codificador AVIF.
        $detectArgs = [string[]]@('identify','-format','%m',$probe)
        $detected = Invoke-Magick -arguments $detectArgs
        $expected = if ($format -eq 'jpg') { 'JPEG' } else { $format.ToUpperInvariant() }
        return ($detected.ExitCode -eq 0 -and $detected.Message.Trim() -eq $expected)
    } catch { return $false }
    finally { if ([IO.File]::Exists($probe)) { [IO.File]::Delete($probe) } }
}
# Al convertir, solo se reintenta el paso de asignar el nombre final.
# Las conversiones fallidas no se vuelven a codificar automaticamente.
function Convert-Images($plan,[string]$format,$quality) {
    # Usar exactamente la carpeta que se reservo al construir el plan.
    if ($plan.Count -eq 0) { throw 'No hay imagenes para convertir.' }
    $dir = Split-Path -Path $plan[0].Destination -Parent
    Ensure-OutputDir $dir
    Header ('TODO A ' + $format.ToUpperInvariant())
    Write-Host 'Procesando imagenes...'
    Write-Host ''
    $converted=0; $errors=0
    $pending=New-Object 'System.Collections.Generic.List[object]'
    $retryReport=New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $plan) {
        $stage=Join-Path $dir ('.ImgMaster_'+[guid]::NewGuid().ToString('N')+'.'+$format)
        $keepStage=$false
        try {
            if (-not [IO.File]::Exists($p.Source)) { throw 'El archivo original ya no existe.' }
            if ([IO.File]::Exists($p.Destination) -or [IO.Directory]::Exists($p.Destination)) {
                throw 'El nombre de salida fue ocupado por otro archivo.'
            }
            $magickArgs = New-Object 'System.Collections.Generic.List[string]'
            [void]$magickArgs.Add(([string]$p.Source + '[0]'))
            [void]$magickArgs.Add('-auto-orient')
            if ($format -eq 'jpg') {
                foreach ($arg in @('-background','white','-alpha','remove','-alpha','off')) {
                    [void]$magickArgs.Add($arg)
                }
            }
            if ($null -ne $quality) {
                [void]$magickArgs.Add('-quality')
                [void]$magickArgs.Add([string]$quality)
            }
            [void]$magickArgs.Add($stage)
            Write-Host ('Convirtiendo: "'+(Split-Path $p.Source -Leaf)+'"  -->  "'+(Split-Path $p.Destination -Leaf)+'"')
            $result = Invoke-Magick $magickArgs.ToArray()
            if ($result.ExitCode -ne 0 -or -not [IO.File]::Exists($stage) -or
                (Get-Item -LiteralPath $stage -ErrorAction SilentlyContinue).Length -eq 0) {
                $detail = $result.Message
                if ([string]::IsNullOrWhiteSpace($detail)) { $detail='ImageMagick no pudo generar la imagen.' }
                throw $detail
            }
            try {
                if ([IO.File]::Exists($p.Destination) -or [IO.Directory]::Exists($p.Destination)) {
                    throw 'El nombre de salida fue ocupado por otro archivo.'
                }
                [IO.File]::Move($stage,$p.Destination)
                $converted++
            } catch {
                # La conversion ya termino: reintentar SOLO mover el temporal.
                $keepStage=$true
                $entry=[pscustomobject]@{Source=$p.Source;Destination=$p.Destination;
                    Stage=$stage;Success=$false;Error=$_.Exception.Message}
                [void]$pending.Add($entry)
                [void]$retryReport.Add($entry)
            }
        } catch {
            $errors++
            Write-Host ('ERROR: '+(Split-Path $p.Source -Leaf)+' - '+$_.Exception.Message) -ForegroundColor Red
        } finally {
            if (-not $keepStage -and [IO.File]::Exists($stage)) {
                try { [IO.File]::Delete($stage) }
                catch { Write-Host ('AVISO: no se pudo eliminar el temporal: '+$stage) -ForegroundColor Yellow }
            }
        }
    }
    # Segundo intento al terminar de procesar el resto del lote.
    foreach ($entry in $pending) {
        try {
            if (-not [IO.File]::Exists($entry.Stage)) { throw 'Ya no existe el temporal.' }
            if ([IO.File]::Exists($entry.Destination) -or [IO.Directory]::Exists($entry.Destination)) {
                throw 'El destino sigue ocupado.'
            }
            [IO.File]::Move($entry.Stage,$entry.Destination)
            $entry.Success=$true
            $converted++
        } catch {
            $entry.Error=$_.Exception.Message
            $errors++
            Write-Host ('ERROR: '+(Split-Path $entry.Source -Leaf)+' - '+$entry.Error) -ForegroundColor Red
        } finally {
            if ([IO.File]::Exists($entry.Stage)) {
                try { [IO.File]::Delete($entry.Stage) }
                catch { Write-Host ('AVISO: temporal sin eliminar: '+$entry.Stage) -ForegroundColor Yellow }
            }
        }
    }
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor DarkGray
    Write-Host '                 RESUMEN' -ForegroundColor Yellow
    Write-Host '==========================================' -ForegroundColor DarkGray
    Write-Host ('Encontradas:  '+$plan.Count)
    Write-Host ('Convertidas:  '+$converted) -ForegroundColor Green
    Write-Host ('Errores:      '+$errors) -ForegroundColor $(if ($errors -gt 0) { 'Red' } else { 'Green' })
    Write-Host '=========================================='
    Show-Retry-Report $retryReport
    Write-Host ''
    Write-Host 'Archivos guardados en:'
    Write-Host ('"'+$dir+'"')
    Write-Host ''
    Wait-User
}

# No se crean historiales, registros JSON ni archivos de recuperacion.
# El plan y los reintentos solo existen en memoria durante esta ejecucion.
function Identity([string]$path,[long]$size,[long]$ticks) {
    if (-not [IO.File]::Exists($path)) { return $false }
    $f=[IO.FileInfo]::new($path)
    return ($f.Length -eq $size -and $f.LastWriteTimeUtc.Ticks -eq $ticks)
}
function Require-Identity([string]$path,$entry) {
    if (-not (Identity $path ([long]$entry.Size) ([long]$entry.Ticks))) {
        throw ('Archivo ausente o modificado; no se tocara: '+$path)
    }
}
function Make-Rename-Plan($files,$names) {
    $plan=@(); $i=0
    foreach ($f in $files) {
        $dest=Join-Path $script:WorkDir ((Number-Name $names $i)+$f.Extension)
        if ($f.FullName -cne $dest) {
            $plan += [pscustomobject]@{
                Source=$f.FullName; Destination=$dest
                Size=[long]$f.Length; Ticks=[long]$f.LastWriteTimeUtc.Ticks
            }
        }
        $i++
    }
    return $plan
}
function Validate-Rename-Plan($plan) {
    $sources=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $targets=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $plan) {
        if (-not $sources.Add($p.Source)) { throw 'Origen duplicado.' }
        if (-not $targets.Add($p.Destination)) { throw ('Destino duplicado: '+$p.Destination) }
        Require-Identity $p.Source $p
        $attrs=[IO.File]::GetAttributes($p.Source)
        if (($attrs -band [IO.FileAttributes]::ReadOnly) -ne 0 -or
            ($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Archivo de solo lectura o enlace no admitido: '+$p.Source)
        }
    }
    foreach ($p in $plan) {
        if (-not $sources.Contains($p.Destination) -and
            ([IO.File]::Exists($p.Destination) -or [IO.Directory]::Exists($p.Destination))) {
            throw ('El nombre ya esta ocupado: '+$p.Destination)
        }
    }
}
function Show-Retry-Report($items) {
    if ($items.Count -eq 0) { return }
    Write-Host ''
    Write-Host 'REINTENTOS' -ForegroundColor Yellow
    Write-Host ''
    foreach ($item in $items) {
        $status=if ($item.Success) { '[CORRECTO]' } else { '[FALLO]' }
        $color=if ($item.Success) { 'Green' } else { 'Red' }
        Write-Host ((Split-Path $item.Source -Leaf)+'  -->  '+
            (Split-Path $item.Destination -Leaf)+'  '+$status) -ForegroundColor $color
    }
}
function New-Rename-Entries($plan) {
    $entries=New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $plan) {
        # Nombre temporal aleatorio, sin revelar el nombre anterior.
        $temp=Join-Path $script:WorkDir ('__ImgMaster_'+[guid]::NewGuid().ToString('N')+'__'+
            [IO.Path]::GetExtension($p.Source))
        [void]$entries.Add([pscustomobject]@{
            Source=$p.Source; Destination=$p.Destination; Temp=$temp;
            Size=[long]$p.Size; Ticks=[long]$p.Ticks; Location='source'
        })
    }
    return $entries
}
# Reversion en dos fases para manejar intercambios de nombres.
# En caso de interrupcion forzada o apagado, no hay historial persistente.
function Rollback-Rename($entries) {
    $problems=New-Object 'System.Collections.Generic.List[string]'
    # Primero retirar todos los nombres finales que hayan sido aplicados.
    foreach ($e in $entries) {
        if ($e.Location -ne 'final') { continue }
        try {
            Require-Identity $e.Destination $e
            if ([IO.File]::Exists($e.Temp) -or [IO.Directory]::Exists($e.Temp)) {
                throw 'El nombre temporal esta ocupado.'
            }
            [IO.File]::Move($e.Destination,$e.Temp)
            $e.Location='temp'
        } catch { [void]$problems.Add(('No se pudo retirar '+$e.Destination+': '+$_.Exception.Message)) }
    }
    # Devolver cada archivo temporal a su nombre anterior.
    foreach ($e in $entries) {
        if ($e.Location -ne 'temp') { continue }
        try {
            Require-Identity $e.Temp $e
            if ([IO.File]::Exists($e.Source) -or [IO.Directory]::Exists($e.Source)) {
                throw 'El nombre original esta ocupado.'
            }
            [IO.File]::Move($e.Temp,$e.Source)
            $e.Location='source'
        } catch { [void]$problems.Add(('No se pudo restaurar '+$e.Source+': '+$_.Exception.Message)) }
    }
    return $problems.ToArray()
}
function Run-Rename-Transaction($plan) {
    Validate-Rename-Plan $plan
    $entries=New-Rename-Entries $plan
    $retryReport=New-Object 'System.Collections.Generic.List[object]'
    $retryIndex=@{}
    $failure=$null
    try {
        # PASO 1: apartar los nombres originales para evitar colisiones.
        $pending=New-Object 'System.Collections.Generic.List[object]'
        foreach ($e in $entries) {
            try {
                Require-Identity $e.Source $e
                [IO.File]::Move($e.Source,$e.Temp)
                $e.Location='temp'
            } catch {
                [void]$pending.Add($e)
                $report=[pscustomobject]@{Source=$e.Source;Destination=$e.Destination;
                    Success=$false;Error=$_.Exception.Message}
                [void]$retryReport.Add($report)
                $retryIndex[$e.Source]=$report
            }
        }
        # Reintentar los que fallaron despues de recorrer todos los demas.
        foreach ($e in $pending) {
            try {
                Require-Identity $e.Source $e
                [IO.File]::Move($e.Source,$e.Temp)
                $e.Location='temp'
                $retryIndex[$e.Source].Success=$true
            } catch { $retryIndex[$e.Source].Error=$_.Exception.Message }
        }
        if (@($entries | Where-Object { $_.Location -ne 'temp' }).Count -gt 0) {
            throw 'No fue posible apartar todas las imagenes, incluso tras reintentar.'
        }
        # PASO 2: aplicar los nombres finales.
        $pending.Clear()
        foreach ($e in $entries) {
            try {
                Require-Identity $e.Temp $e
                if ([IO.File]::Exists($e.Destination) -or [IO.Directory]::Exists($e.Destination)) {
                    throw 'El destino esta ocupado.'
                }
                [IO.File]::Move($e.Temp,$e.Destination)
                $e.Location='final'
                Write-Host ((Split-Path $e.Source -Leaf)+'  -->  '+(Split-Path $e.Destination -Leaf))
            } catch {
                [void]$pending.Add($e)
                if (-not $retryIndex.ContainsKey($e.Source)) {
                    $report=[pscustomobject]@{Source=$e.Source;Destination=$e.Destination;
                        Success=$false;Error=$_.Exception.Message}
                    [void]$retryReport.Add($report)
                    $retryIndex[$e.Source]=$report
                } else {
                    $retryIndex[$e.Source].Success=$false
                    $retryIndex[$e.Source].Error=$_.Exception.Message
                }
            }
        }
        # Segundo intento del nombre definitivo, al terminar el lote.
        foreach ($e in $pending) {
            try {
                Require-Identity $e.Temp $e
                if ([IO.File]::Exists($e.Destination) -or [IO.Directory]::Exists($e.Destination)) {
                    throw 'El destino sigue ocupado.'
                }
                [IO.File]::Move($e.Temp,$e.Destination)
                $e.Location='final'
                $retryIndex[$e.Source].Success=$true
                Write-Host ((Split-Path $e.Source -Leaf)+'  -->  '+(Split-Path $e.Destination -Leaf))
            } catch { $retryIndex[$e.Source].Error=$_.Exception.Message }
        }
        if (@($entries | Where-Object { $_.Location -ne 'final' }).Count -gt 0) {
            throw 'Algunas imagenes siguen sin poder renombrarse despues del reintento.'
        }
    } catch { $failure=$_.Exception.Message }
    if ($null -ne $failure) {
        $rollbackProblems=@(Rollback-Rename $entries)
        # Los reintentos pudieron funcionar, pero se revirtio el lote.
        foreach ($r in $retryReport) { $r.Success=$false }
        if ($rollbackProblems.Count -gt 0) {
            Write-Host 'ATENCION: recuperacion incompleta.' -ForegroundColor Red
            foreach ($problem in $rollbackProblems) { Write-Host $problem -ForegroundColor Red }
            foreach ($e in $entries) {
                if ($e.Location -ne 'source') {
                    Write-Host ('RECUPERAR MANUALMENTE: '+
                        $(if ($e.Location -eq 'temp') { $e.Temp } else { $e.Destination })+
                        '  -->  '+$e.Source) -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host 'Se revirtieron los cambios para proteger los nombres originales.' -ForegroundColor Yellow
        }
        Write-Host ('ERROR: '+$failure) -ForegroundColor Red
        return [pscustomobject]@{Renamed=0;Errors=[Math]::Max(1,$retryReport.Count);
            Retries=$retryReport;Failed=$true}
    }
    return [pscustomobject]@{Renamed=$entries.Count;Errors=0;Retries=$retryReport;Failed=$false}
}
function Rename-Only {
    $order=Ask-Order
    if ($order -eq '4') { return }
    $files=@(Image-Files $order)
    if ($files.Count -eq 0) { Write-Host 'No se encontraron imagenes compatibles.'; Wait-User; return }
    $names=Ask-Names
    if ($null -eq $names) { return }
    try {
        $plan=@(Make-Rename-Plan $files $names)
        if ($plan.Count -eq 0) { Write-Host 'Los archivos ya tienen esos nombres.'; Wait-User; return }
        Validate-Rename-Plan $plan
        Header 'RENOMBRANDO IMAGENES'
        $result=Run-Rename-Transaction $plan
        Write-Host ''
        Write-Host '==========================================' -ForegroundColor DarkGray
        Write-Host '                 RESUMEN' -ForegroundColor Yellow
        Write-Host '==========================================' -ForegroundColor DarkGray
        Write-Host ('Encontradas:  '+$files.Count)
        Write-Host ('Renombradas:  '+$result.Renamed) -ForegroundColor Green
        Write-Host ('Errores:      '+$result.Errors) -ForegroundColor $(if ($result.Errors -gt 0) { 'Red' } else { 'Green' })
        Write-Host '=========================================='
        Show-Retry-Report $result.Retries
    } catch { Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red }
    Wait-User
}
function Convert-Menu([string]$format) {
    if (-not (Check-Format $format)) {
        Write-Host ('ERROR: ImageMagick no puede generar archivos '+$format.ToUpperInvariant()+'.') -ForegroundColor Red
        Wait-User; return
    }
    $quality=Ask-Quality $format
    if ($quality -eq -1) { return }
    Header ('TODO A '+$format.ToUpperInvariant())
    Write-Host 'Deseas renombrar las imagenes al convertirlas?'
    Write-Host ''
    Write-Host '1. Si'
    Write-Host '2. No'
    Write-Host '3. Volver'
    Write-Host ''
    $choice=Ask 'Seleccione una opcion' @('1','2','3')
    if ($choice -eq '3') { return }
    $names=$null; $order='1'
    if ($choice -eq '1') {
        $order=Ask-Order
        if ($order -eq '4') { return }
        $names=Ask-Names
        if ($null -eq $names) { return }
    }
    try {
        $files=@(Image-Files $order)
        if ($files.Count -eq 0) { Write-Host 'No se encontraron imagenes compatibles.'; Wait-User; return }
        $plan=@(Make-Convert-Plan $files $format $names $quality)
        Convert-Images $plan $format $quality
    } catch { Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red; Wait-User }
}

# Herramientas adicionales: todas trabajan sobre la carpeta actual,
# conservan los originales y no guardan historiales de archivos.
$script:EditableFormats = @('.jpg','.jpeg','.jfif','.png','.webp','.avif','.bmp',
    '.tif','.tiff','.heic','.heif')
$script:CompressFormats = @('.jpg','.jpeg','.jfif','.png','.webp','.avif')

function Ask-PositiveInteger([string]$prompt) {
    while ($true) {
        $value=(Read-Host ($prompt+' (V para volver)')).Trim()
        if ($value -ieq 'v') { return 0 }
        $parsed=0
        if ([int]::TryParse($value,[ref]$parsed) -and $parsed -ge 1 -and $parsed -le 100000) {
            return $parsed
        }
        Write-Host 'Introduce un entero entre 1 y 100000.' -ForegroundColor Yellow
    }
}
function Get-ToolOutputDir([string]$label) {
    $root=Get-ResultsRoot
    $leaf=Split-Path -Path $script:WorkDir -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf='Imagenes' }
    $base=$leaf+' - '+$label
    $used=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($root)) {
        [void]$used.Add([IO.Path]::GetFileName($path))
    }
    if (-not $used.Contains($base)) { return (Join-Path $root $base) }
    for ($i=2;$i -le 1000000;$i++) {
        $name=$base+' ('+$i+')'
        if (-not $used.Contains($name)) { return (Join-Path $root $name) }
    }
    throw 'No hay un nombre de carpeta disponible.'
}
function Get-Image-Dimensions([string]$path,[bool]$autoOrient) {
    $argsList=New-Object 'System.Collections.Generic.List[string]'
    [void]$argsList.Add(($path+'[0]'))
    if ($autoOrient) { [void]$argsList.Add('-auto-orient') }
    foreach ($a in @('-format','%w %h','info:')) { [void]$argsList.Add($a) }
    $result=Invoke-Magick $argsList.ToArray()
    if ($result.ExitCode -ne 0 -or $result.Message -notmatch '^\s*(\d+)\s+(\d+)\s*$') {
        throw 'No se pudo leer la resolucion de la imagen.'
    }
    return [pscustomobject]@{ W=[int]$Matches[1]; H=[int]$Matches[2] }
}
function Process-ToolBatch([string]$action,$settings) {
    $files=@(Image-Files '1')
    if ($files.Count -eq 0) {
        Write-Host 'No se encontraron imagenes compatibles.' -ForegroundColor Yellow
        Wait-User; return
    }
    $dir=$null
    $done=0; $skipped=0; $errors=0; $retryHeadingShown=$false
    Header $action
    Write-Host ('Carpeta analizada: '+$script:WorkDir)
    Write-Host 'Procesando imagenes...'
    Write-Host ''
    $queue=New-Object 'System.Collections.Generic.Queue[object]'
    foreach ($f in $files) { $queue.Enqueue([pscustomobject]@{File=$f;Attempt=1}) }
    while ($queue.Count -gt 0) {
        $job=$queue.Dequeue()
        $f=$job.File
        if ($job.Attempt -eq 2 -and -not $retryHeadingShown) {
            Write-Host ''; Write-Host 'REINTENTOS DE PROCESAMIENTO' -ForegroundColor Yellow
            $retryHeadingShown=$true
        }
        $stage=$null
        try {
            $ext=$f.Extension.ToLowerInvariant()
            $allowed=if ($action -eq 'COMPRIMIR IMAGENES') {
                $script:CompressFormats
            } else { $script:EditableFormats }
            if ($allowed -notcontains $ext) {
                $skipped++
                Write-Host ('OMITIDA: '+$f.Name+' (formato no admitido para esta herramienta)') -ForegroundColor DarkYellow
                continue
            }
            if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $skipped++
                Write-Host ('OMITIDA: '+$f.Name+' (enlace o acceso indirecto)') -ForegroundColor DarkYellow
                continue
            }
            $dimensions=$null
            $angle=0
            $geometry=''
            if ($action -eq 'REDIMENSIONAR IMAGENES') {
                $dimensions=Get-Image-Dimensions $f.FullName $true
                $enlarge=($settings.ResizeAction -eq 'ampliar')
                $modifier=if ($enlarge) { '<' } else { '>' }
                if ($settings.Mode -eq 'alto') {
                    $geometry='x'+$settings.Height+$modifier
                    $shouldResize=if ($enlarge) { $dimensions.H -lt $settings.Height } else { $dimensions.H -gt $settings.Height }
                } elseif ($settings.Mode -eq 'ancho') {
                    $geometry=[string]$settings.Width+'x'+$modifier
                    $shouldResize=if ($enlarge) { $dimensions.W -lt $settings.Width } else { $dimensions.W -gt $settings.Width }
                } else {
                    $geometry=[string]$settings.Width+'x'+$settings.Height+$modifier
                    if ($enlarge) {
                        # Ampliar proporcionalmente hasta el limite que se alcance primero.
                        $shouldResize=([math]::Min($settings.Width / [double]$dimensions.W,
                            $settings.Height / [double]$dimensions.H) -gt 1.0)
                    } else {
                        $shouldResize=($dimensions.W -gt $settings.Width -or $dimensions.H -gt $settings.Height)
                    }
                }
                if (-not $shouldResize) {
                    $skipped++
                    $reason=if ($enlarge) { 'ya alcanza o supera la resolucion elegida' } else { 'no supera la resolucion elegida' }
                    Write-Host ('SIN CAMBIOS: '+$f.Name+' ('+$reason+')')
                    continue
                }
            } elseif ($action -eq 'GIRAR IMAGENES') {
                $dimensions=Get-Image-Dimensions $f.FullName $true
                if ($settings.Target -eq 'invertir') {
                    # Invertir 180 grados todas las imagenes, sin cambiar orientacion.
                    $angle=180
                } else {
                    # Vertical / horizontal es la orientacion FINAL solicitada.
                    # Girar solo imagenes con la orientacion contraria.
                    $matches=if ($settings.Target -eq 'vertical') {
                        $dimensions.W -gt $dimensions.H
                    } else { $dimensions.H -gt $dimensions.W }
                    if (-not $matches) {
                        $skipped++
                        Write-Host ('SIN CAMBIOS: '+$f.Name+' (no coincide con la orientacion elegida o es cuadrada)')
                        continue
                    }
                    $angle=if ($settings.Direction -eq 'derecha') { 90 } else { -90 }
                }
            }
            if ($null -eq $dir) {
                $label=switch ($action) {
                    'REDIMENSIONAR IMAGENES' {
                        $prefix=if ($settings.ResizeAction -eq 'ampliar') { 'AMPLIADAS' } else { 'REDIMENSIONADAS' }
                        if ($settings.Mode -eq 'alto') { $prefix+' - ALTO '+$settings.Height+'px' }
                        elseif ($settings.Mode -eq 'ancho') { $prefix+' - ANCHO '+$settings.Width+'px' }
                        else { $prefix+' - '+$settings.Width+'x'+$settings.Height+'px' }
                    }
                    'COMPRIMIR IMAGENES' { 'COMPRIMIDAS - CALIDAD '+$settings.Quality+'%' }
                    'GIRAR IMAGENES' { if ($settings.Target -eq 'invertir') { 'GIRADAS - INVERTIDAS' } else { 'GIRADAS - '+$settings.Target.ToUpperInvariant() } }
                }
                $dir=Get-ToolOutputDir $label
                # Si otro proceso ocupo la ruta, buscar una nueva en lugar de reutilizarla.
                for ($attemptDir=0; $attemptDir -lt 10; $attemptDir++) {
                    if ([IO.File]::Exists($dir) -or [IO.Directory]::Exists($dir)) {
                        $dir=Get-ToolOutputDir $label
                        continue
                    }
                    Ensure-OutputDir $dir
                    break
                }
                if (-not [IO.Directory]::Exists($dir)) { throw 'No se pudo crear una carpeta de salida libre.' }
            }
            $stage=Join-Path $dir ('.ImgMaster_'+[guid]::NewGuid().ToString('N')+$ext)
            $argsList=New-Object 'System.Collections.Generic.List[string]'
            [void]$argsList.Add(($f.FullName+'[0]'))
            if ($action -eq 'REDIMENSIONAR IMAGENES') {
                [void]$argsList.Add('-auto-orient')
                [void]$argsList.Add('-resize')
                [void]$argsList.Add($geometry)
                # > reduce solamente; < amplia solamente, conservando proporciones.
            } elseif ($action -eq 'GIRAR IMAGENES') {
                [void]$argsList.Add('-auto-orient')
                [void]$argsList.Add('-rotate')
                [void]$argsList.Add([string]$angle)
            } else {
                if ($ext -eq '.png') {
                    [void]$argsList.Add('-define')
                    [void]$argsList.Add('png:compression-level=9')
                } else {
                    [void]$argsList.Add('-quality')
                    [void]$argsList.Add([string]$settings.Quality)
                }
            }
            [void]$argsList.Add($stage)
            $result=Invoke-Magick $argsList.ToArray()
            if ($result.ExitCode -ne 0 -or -not [IO.File]::Exists($stage) -or
                ([IO.FileInfo]::new($stage)).Length -eq 0) {
                throw ('ImageMagick no pudo procesar la imagen. '+$result.Message)
            }
            if ($action -eq 'COMPRIMIR IMAGENES') {
                $newDims=Get-Image-Dimensions $stage $false
                $oldDims=Get-Image-Dimensions $f.FullName $false
                if ($newDims.W -ne $oldDims.W -or $newDims.H -ne $oldDims.H) {
                    throw 'La compresion cambio las dimensiones; resultado descartado.'
                }
                $newSize=([IO.FileInfo]::new($stage)).Length
                if ($newSize -ge $f.Length) {
                    $skipped++
                    Write-Host ('SIN CAMBIOS: '+$f.Name+' (la compresion no redujo su peso)')
                    continue
                }
            }
            # Se crea una carpeta nueva por lote; no se sobreescribe el origen.
            $target=Join-Path $dir $f.Name
            if ([IO.File]::Exists($target) -or [IO.Directory]::Exists($target)) {
                throw ('El nombre de salida esta ocupado: '+$target)
            }
            [IO.File]::Move($stage,$target)
            $done++
            Write-Host ('CORRECTO: '+$f.Name+'  -->  '+(Split-Path $target -Leaf)) -ForegroundColor Green
        } catch {
            if ($job.Attempt -eq 1) {
                Write-Host ('AVISO: '+$f.Name+' - fallo inicial; se reintentara al final.') -ForegroundColor Yellow
                $queue.Enqueue([pscustomobject]@{File=$f;Attempt=2})
            } else {
                $errors++
                Write-Host ('ERROR: '+$f.Name+' - '+$_.Exception.Message) -ForegroundColor Red
            }
        } finally {
            if ($null -ne $stage -and [IO.File]::Exists($stage)) {
                try { [IO.File]::Delete($stage) }
                catch { Write-Host ('AVISO: temporal sin eliminar: '+$stage) -ForegroundColor Yellow }
            }
        }
    }
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor DarkGray
    Write-Host '                 RESUMEN' -ForegroundColor Yellow
    Write-Host '==========================================' -ForegroundColor DarkGray
    Write-Host ('Encontradas:  '+$files.Count)
    Write-Host ('Procesadas:   '+$done) -ForegroundColor Green
    Write-Host ('Sin cambios:  '+$skipped)
    Write-Host ('Errores:      '+$errors) -ForegroundColor $(if ($errors -gt 0) { 'Red' } else { 'Green' })
    Write-Host '==========================================' -ForegroundColor DarkGray
    if ($null -ne $dir) {
        Write-Host 'Archivos guardados en:'
        Write-Host ('"'+$dir+'"')
    } else {
        Write-Host 'No se generaron archivos nuevos.'
    }
    Write-Host ''
    Wait-User
}
function Resize-Menu {
    Header 'REDIMENSIONAR IMAGENES'
    Write-Host '1. Reducir imagenes'
    Write-Host '2. Ampliar imagenes'
    Write-Host '3. Volver'
    Write-Host ''
    $resizeChoice=Ask 'Seleccione una opcion' @('1','2','3')
    if ($resizeChoice -eq '3') { return }
    $resizeAction=if ($resizeChoice -eq '2') { 'ampliar' } else { 'reducir' }
    Header $(if ($resizeAction -eq 'ampliar') { 'AMPLIAR IMAGENES' } else { 'REDUCIR IMAGENES' })
    Write-Host '1. Alto (ancho automatico)'
    Write-Host '2. Ancho (alto automatico)'
    Write-Host '3. Personalizar alto y ancho'
    Write-Host '4. Volver'
    Write-Host ''
    $v=Ask 'Seleccione una opcion' @('1','2','3','4')
    if ($v -eq '4') { return }
    $settings=[pscustomobject]@{Mode='';Width=0;Height=0;OnlyLarger=$false;ResizeAction=$resizeAction}
    if ($v -eq '1') {
        $settings.Mode='alto'
        $settings.Height=Ask-PositiveInteger 'Coloque la resolucion de alto'
        if ($settings.Height -eq 0) { return }
    } elseif ($v -eq '2') {
        $settings.Mode='ancho'
        $settings.Width=Ask-PositiveInteger 'Coloque la resolucion de ancho'
        if ($settings.Width -eq 0) { return }
    } else {
        $settings.Mode='personalizar'
        $settings.Height=Ask-PositiveInteger 'Coloque la resolucion de alto'
        if ($settings.Height -eq 0) { return }
        $settings.Width=Ask-PositiveInteger 'Coloque la resolucion de ancho'
        if ($settings.Width -eq 0) { return }
        Write-Host 'Se conservaran las proporciones; ambas medidas son limites maximos.' -ForegroundColor Yellow
    }
    if ($resizeAction -eq 'reducir') {
        Header 'APLICAR REDIMENSION'
        Write-Host '1. Todas las imagenes'
        Write-Host '2. Solo imagenes que superen la resolucion elegida'
        Write-Host '3. Volver'
        Write-Host ''
        $scope=Ask 'Seleccione una opcion' @('1','2','3')
        if ($scope -eq '3') { return }
        $settings.OnlyLarger=($scope -eq '2')
    } else {
        Write-Host 'Solo se ampliaran las imagenes que no alcancen las dimensiones elegidas.' -ForegroundColor Yellow
        Write-Host 'La ampliacion no recupera detalles que no existan en la imagen original.' -ForegroundColor Yellow
    }
    Process-ToolBatch 'REDIMENSIONAR IMAGENES' $settings
}
function Compress-Menu {
    Header 'COMPRIMIR IMAGENES'
    Write-Host 'Calidad para JPG, WEBP y AVIF (PNG usa compresion sin perdida).'
    Write-Host 'Aviso: comprimir puede modificar metadatos o recodificar la imagen.' -ForegroundColor Yellow
    Write-Host '1. Predeterminada (80)'
    Write-Host '2. Personalizada (1-100)'
    Write-Host '3. Volver'
    Write-Host ''
    $v=Ask 'Seleccione una opcion' @('1','2','3')
    if ($v -eq '3') { return }
    $quality=80
    if ($v -eq '2') {
        while ($true) {
            $n=(Read-Host 'Calidad (1-100, V para volver)').Trim()
            if ($n -ieq 'v') { return }
            $parsed=0
            if ([int]::TryParse($n,[ref]$parsed) -and $parsed -ge 1 -and $parsed -le 100) {
                $quality=$parsed; break
            }
            Write-Host 'Introduce un numero entre 1 y 100.' -ForegroundColor Yellow
        }
    }
    Process-ToolBatch 'COMPRIMIR IMAGENES' ([pscustomobject]@{Quality=$quality})
}
# Calcula una firma de los pixeles decodificados, no de los metadatos.
# El archivo temporal RAW se elimina siempre, incluso si ImageMagick falla.
function Get-Pixel-Signature([string]$path) {
    $raw=Join-Path ([IO.Path]::GetTempPath()) ('ImgMaster_pixels_'+[guid]::NewGuid().ToString('N')+'.rgba')
    try {
        $dim=Get-Image-Dimensions $path $true
        # Crear un arreglo tipado y pasarlo como un unico parametro de la funcion.
        # NO usar Invoke-Magick @(...) directamente: PowerShell puede interpretar
        # los elementos como argumentos posicionales de la funcion envoltorio.
        $pixelArgs = [string[]]@(
            ($path+'[0]'), '-auto-orient', '-colorspace', 'sRGB',
            '-alpha', 'on', '-depth', '8', ('RGBA:'+$raw)
        )
        $result=Invoke-Magick -arguments $pixelArgs
        if ($result.ExitCode -ne 0 -or -not [IO.File]::Exists($raw)) {
            $detail=($result.Message -split '[\r\n]+' | Where-Object { $_ -match '^(magick(\.exe)?:|ERROR:|Warning:)' } | Select-Object -First 1)
            if (-not $detail) { $detail='ImageMagick no pudo decodificar la imagen.' }
            throw ('No se pudo decodificar: '+$detail)
        }
        $expected=[long]$dim.W*[long]$dim.H*4L
        if (([IO.FileInfo]::new($raw)).Length -ne $expected) {
            throw 'Los datos de pixeles tienen una longitud inesperada.'
        }
        $hash=(Get-FileHash -LiteralPath $raw -Algorithm SHA256 -ErrorAction Stop).Hash
        return ([string]$dim.W+'x'+[string]$dim.H+':'+$hash)
    } finally {
        if ([IO.File]::Exists($raw)) { [IO.File]::Delete($raw) }
    }
}
function Duplicates-Menu {
    Header 'DETECTAR DUPLICADOS'
    if ($script:HasMagick) {
        Write-Host '1. Buscar duplicados (archivos identicos y mismos pixeles)'
    } else {
        Write-Host '1. Buscar duplicados (archivos exactamente identicos)'
    }
    Write-Host '2. Volver'
    Write-Host ''
    if ((Ask 'Seleccione una opcion' @('1','2')) -eq '2') { return }
    $files=@(Image-Files '1')
    Header 'DETECTAR DUPLICADOS'
    Write-Host ('Carpeta analizada: '+$script:WorkDir)
    Write-Host ('Imagenes encontradas: '+$files.Count)
    if ($script:HasMagick) {
        Write-Host 'Comparando archivos identicos y contenido de pixeles...'
    } else {
        Write-Host 'Comparando archivos identicos por SHA-256 (sin ImageMagick)...'
    }
    Write-Host ''
    $bins=@{}; $pixels=@{}; $errors=0; $analyzed=0; $pixelErrors=0
    foreach ($f in $files) {
        try {
            if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $bin=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $binKey='BIN:'+ $bin
            if (-not $bins.ContainsKey($binKey)) { $bins[$binKey]=New-Object 'System.Collections.Generic.List[object]' }
            [void]$bins[$binKey].Add($f)
            if ($script:HasMagick) {
                # Comparar pixeles RGBA reales, normalizados a sRGB y orientados.
                # Los errores de lectura se contabilizan sin inundar la consola.
                try {
                    $signature=Get-Pixel-Signature $f.FullName
                    $key='PIX:'+$signature
                    if (-not $pixels.ContainsKey($key)) { $pixels[$key]=New-Object 'System.Collections.Generic.List[object]' }
                    [void]$pixels[$key].Add($f)
                } catch {
                    $pixelErrors++
                    if ($pixelErrors -le 3) {
                        Write-Host ('AVISO: Comparacion de pixeles no disponible para '+$f.Name+': '+$_.Exception.Message) -ForegroundColor Yellow
                    }
                }
            }
            $analyzed++
        } catch {
            $errors++
            Write-Host ('ERROR: '+$f.Name+' - '+$_.Exception.Message) -ForegroundColor Red
        }
    }
    # Union-find agrupando archivos que coinciden por hash binario O por pixeles.
    $parent=@{}
    foreach ($f in $files) { $parent[$f.FullName]=$f.FullName }
    foreach ($collection in @($bins,$pixels)) {
        foreach ($group in $collection.Values) {
            if ($group.Count -lt 2) { continue }
            $first=$group[0].FullName
            foreach ($item in $group) {
                $rootA=$first; while ($parent[$rootA] -cne $rootA) { $rootA=$parent[$rootA] }
                $rootB=$item.FullName; while ($parent[$rootB] -cne $rootB) { $rootB=$parent[$rootB] }
                if ($rootA -cne $rootB) { $parent[$rootB]=$rootA }
            }
        }
    }
    $groups=@{}
    foreach ($f in $files) {
        $root=$f.FullName; while ($parent[$root] -cne $root) { $root=$parent[$root] }
        if (-not $groups.ContainsKey($root)) { $groups[$root]=New-Object 'System.Collections.Generic.List[object]' }
        [void]$groups[$root].Add($f)
    }
    # Orden natural: los archivos ya llegan ordenados por ImgMasterNaturalComparer.
    # Ordenar los grupos por la posicion de su primer archivo en ese mismo orden,
    # evitando el orden alfabetico que coloca 130.png antes de 56.png.
    $fileOrder=@{}
    for ($i=0; $i -lt $files.Count; $i++) { $fileOrder[$files[$i].FullName]=$i }
    $groupCount=0; $extra=0
    foreach ($group in @($groups.Values | Where-Object { $_.Count -gt 1 } | Sort-Object { $fileOrder[$_[0].FullName] })) {
        $groupCount++; $extra += $group.Count-1
        Write-Host ''
        Write-Host ('GRUPO '+$groupCount+' - '+$group.Count+' archivos duplicados') -ForegroundColor Yellow
        foreach ($f in $group) { Write-Host ('  '+$f.Name) }
    }
    if ($groupCount -eq 0) { Write-Host 'No se encontraron duplicados.' -ForegroundColor Green }
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor DarkGray
    Write-Host '                 RESUMEN' -ForegroundColor Yellow
    Write-Host '==========================================' -ForegroundColor DarkGray
    Write-Host ('Encontradas:       '+$files.Count)
    Write-Host ('Analizadas:        '+$analyzed)
    Write-Host ('Grupos duplicados: '+$groupCount)
    Write-Host ('Copias adicionales: '+$extra)
    Write-Host ('Errores:           '+$errors) -ForegroundColor $(if ($errors -gt 0) { 'Red' } else { 'Green' })
    if ($script:HasMagick) {
        Write-Host ('Comparaciones de pixeles fallidas: '+$pixelErrors) -ForegroundColor $(if ($pixelErrors -gt 0) { 'Red' } else { 'Green' })
        if ($pixelErrors -gt 3) { Write-Host ('Se omitieron '+($pixelErrors-3)+' avisos adicionales; revisa el total de fallos.') -ForegroundColor Yellow }
    } else {
        Write-Host 'Sin ImageMagick: solo se detectaron archivos exactamente identicos.' -ForegroundColor Yellow
    }
    Write-Host '==========================================' -ForegroundColor DarkGray
    Write-Host 'Ningun archivo fue modificado.' -ForegroundColor Green
    Wait-User
}
function Rotate-Menu {
    Header 'GIRAR IMAGENES'
    Write-Host 'Como quieres que queden las imagenes?'
    Write-Host '1. Vertical'
    Write-Host '2. Horizontal'
    Write-Host '3. Invertir (180 grados)'
    Write-Host '4. Volver'
    Write-Host ''
    $v=Ask 'Seleccione una opcion' @('1','2','3','4')
    if ($v -eq '4') { return }
    if ($v -eq '3') {
        Process-ToolBatch 'GIRAR IMAGENES' ([pscustomobject]@{Target='invertir';Direction=''})
        return
    }
    $target=if ($v -eq '1') { 'vertical' } else { 'horizontal' }
    Header 'DIRECCION DE GIRO'
    Write-Host '1. Derecha (90 grados)'
    Write-Host '2. Izquierda (90 grados)'
    Write-Host '3. Volver'
    Write-Host ''
    $d=Ask 'Seleccione una opcion' @('1','2','3')
    if ($d -eq '3') { return }
    $direction=if ($d -eq '1') { 'derecha' } else { 'izquierda' }
    Process-ToolBatch 'GIRAR IMAGENES' ([pscustomobject]@{Target=$target;Direction=$direction})
}

function Install-Magick {
    Header 'INSTALAR IMAGEMAGICK'
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Host 'ERROR: winget no esta disponible.' -ForegroundColor Red; Wait-User; return
    }
    Write-Host 'Se instalara ImageMagick mediante winget.'
    if ((Ask '1. Instalar   2. Volver' @('1','2')) -ne '1') { return }
    & winget.exe install -e --id ImageMagick.ImageMagick --accept-package-agreements --accept-source-agreements
    Write-Host ''
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Instalacion finalizada. Cierra y vuelve a abrir ImgMaster.' -ForegroundColor Green
    } else {
        Write-Host ('ERROR: winget devolvio el codigo '+$LASTEXITCODE) -ForegroundColor Red
    }
    Wait-User
}
function Main {
    while ($true) {
        $script:HasMagick = ($null -ne (Get-Command magick.exe -ErrorAction SilentlyContinue))
        Header 'ImgMaster'
        Write-Host ('CARPETA DE IMAGENES: '+$script:WorkDir)
        Write-Host ('RESULTADOS: '+(Get-ResultsRoot))
        Write-Host ''
        if ($script:HasMagick) {
            Write-Host ('{0,-23}{1}' -f 'CONVERSION','HERRAMIENTAS') -ForegroundColor Yellow
            Write-Host ('{0,-23}{1}' -f '1. TODO A PNG','6. RENOMBRAR')
            Write-Host ('{0,-23}{1}' -f '2. TODO A JPG','7. REDIMENSIONAR')
            Write-Host ('{0,-23}{1}' -f '3. TODO A WEBP','8. COMPRIMIR')
            Write-Host ('{0,-23}{1}' -f '4. TODO A AVIF','9. DETECTAR DUPLICADOS')
            Write-Host ('{0,-23}{1}' -f '5. TODO A BMP','10. GIRAR IMAGENES')
            Write-Host ''
            Write-Host '11. SELECCIONAR CARPETA'
            if ($script:ExternalFolderSelected) { Write-Host '12. RESTABLECER CARPETA ORIGINAL' }
            Write-Host ''
            $choices=@('1','2','3','4','5','6','7','8','9','10','11')
            if ($script:ExternalFolderSelected) { $choices+= '12' }
            $v=Ask 'Seleccione una opcion' $choices
            switch ($v) {
                '1' { Convert-Menu 'png' }
                '2' { Convert-Menu 'jpg' }
                '3' { Convert-Menu 'webp' }
                '4' { Convert-Menu 'avif' }
                '5' { Convert-Menu 'bmp' }
                '6' { Rename-Only }
                '7' { Resize-Menu }
                '8' { Compress-Menu }
                '9' { Duplicates-Menu }
                '10' { Rotate-Menu }
                '11' { Select-ImagesFolder }
                '12' { Restore-InitialFolder }
            }
        } else {
            Write-Host 'Para convertir imagenes se necesita ImageMagick.'
            Write-Host ''
            Write-Host '1. Instalar ImageMagick'
            Write-Host '2. Renombrar imagenes'
            Write-Host '3. Detectar duplicados'
            Write-Host '11. Seleccionar carpeta'
            if ($script:ExternalFolderSelected) { Write-Host '12. Restablecer carpeta original' }
            Write-Host ''
            Write-Host 'Redimensionar, comprimir y girar requieren ImageMagick.' -ForegroundColor Yellow
            Write-Host ''
            $choices=@('1','2','3','11')
            if ($script:ExternalFolderSelected) { $choices+= '12' }
            $v=Ask 'Seleccione una opcion' $choices
            switch ($v) {
                '1' { Install-Magick }
                '2' { Rename-Only }
                '3' { Duplicates-Menu }
                '11' { Select-ImagesFolder }
                '12' { Restore-InitialFolder }
            }
        }
    }
}
Main
