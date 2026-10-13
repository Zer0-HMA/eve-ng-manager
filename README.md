# eve-ng-manager

Instala y gestiona **EVE-NG** en **Arch Linux** usando **QEMU/KVM + libvirt**, desde cero y sin complicaciones.

- **`setup.sh`** instala todo lo necesario, configura el sistema y crea la VM de EVE-NG a partir de la ISO que tú descargues.
- **`eve`** es el comando del día a día: enciende EVE-NG, abre la web y te deja subir imágenes mientras practicas.
- **`vms`** maneja tus máquinas de prueba con **Linux, Windows y macOS**: escoges una o varias y se encienden con su ventana.

## Inicio rápido

```bash
git clone https://github.com/Zer0-HMA/eve-ng-manager.git
cd eve-ng-manager
./setup.sh
```

Elige **1) Instalación completa** y sigue las instrucciones. Cuando termine:

```bash
eve
```

## Antes de empezar

1. **Activa la virtualización en la BIOS/UEFI**: SVM / AMD-V en AMD, VT-x en Intel. El instalador te avisa si falta.
2. **Descarga la ISO de EVE-NG Community** (gratis) desde [eve-ng.net](https://www.eve-ng.net), en la sección *Downloads*. Déjala en `~/Descargas` o `~/Downloads` y el instalador la encontrará sola.

Este proyecto no incluye ni distribuye la ISO de EVE-NG ni imágenes de ningún fabricante.

## Qué hace `setup.sh`

| Paso | Qué hace |
|------|----------|
| 1 | Revisa que tu CPU soporte virtualización |
| 2 | Instala `qemu-desktop`, `libvirt`, `virt-install`, `virt-manager`, `virt-viewer`, `dnsmasq`, `openssh`, `rsync`, `xdg-utils`, `edk2-ovmf` (UEFI), `swtpm` (TPM) y `socat` |
| 3 | Activa `libvirtd` y te agrega al grupo `libvirt` |
| 4 | Activa la red virtual `default` (NAT + DHCP) |
| 5 | Activa la virtualización anidada (para que los nodos de EVE-NG vayan rápido) |
| 6 | Instala los comandos `eve` y `vms` en `~/.local/bin` |
| 7 | Crea la VM de EVE-NG con la ISO, sugiriendo RAM y CPU según tu PC |
| 8 | Opcional: `quickemu` (para macOS y descargar ISOs solas) y `virtio-win` (drivers de Windows), desde el repo o el AUR con `yay`/`paru` |

Puedes ejecutar cada paso por separado desde el menú. Si ya tenías algo instalado, lo detecta y lo salta.

Opciones sin menú:

```bash
./setup.sh --all        # instalación completa
./setup.sh --check      # diagnóstico: revisa que todo esté bien
./setup.sh --uninstall  # quita los comandos 'eve' y 'vms' (no toca las VMs)
```

### Durante la instalación de EVE-NG

Se abre una ventana con la pantalla de la VM. En el primer arranque EVE-NG te pregunta algunas cosas:

- **Contraseña de root**: anótala, el comando `eve` la usa para conectarse por SSH.
- **Hostname y dominio**: puedes dejar los valores por defecto.
- **Red**: elige `dhcp`.

Al terminar, el instalador retira la ISO de la VM automáticamente.

## Uso diario: `eve`

```bash
eve
```

Enciende la VM, espera a que EVE-NG arranque, abre la web y muestra este menú:

| Opción | Acción |
|--------|--------|
| 1 | Subir imagen QEMU (`.qcow2`; convierte `.vmdk`, `.ova`, `.img`, `.vhd`, `.vdi`) |
| 2 | Subir ISO para instalar un sistema (crea también el disco) |
| 3 | Subir imagen IOL (`.bin`) |
| 4 | Subir imagen Dynamips (`.image`) |
| 5 | Ver imágenes instaladas |
| 6 | Borrar imagen QEMU |
| 7 | Estado de la VM |
| 8 | Abrir la web |
| 9 | Abrir consola SSH |
| k | Configurar llave SSH (no volver a escribir la contraseña) |
| v | Abrir `vms` (máquinas de prueba) |
| 0 | Salir (pregunta si apagar la VM) |

Para elegir un archivo puedes escribir la ruta (Tab autocompleta) o arrastrarlo a la terminal. Después de cada subida se arreglan los permisos de EVE-NG automáticamente.

Si la VM se apaga mientras `eve` está abierto, el script lo detecta y se cierra.

### En la web de EVE-NG

- Usuario por defecto: `admin` / `eve`.
- Al iniciar sesión elige consola **HTML5**: así abres los equipos desde el navegador sin instalar nada más.

## Máquinas de prueba: `vms`

Para probar sistemas fuera de EVE-NG: una Ubuntu, un Windows 11, un macOS, o varias a la vez.

```bash
vms                       # menú
vms list                  # ver todas
vms start ubuntu24 win11  # encender varias y abrir sus ventanas
vms stop ubuntu24 win11
vms new                   # crear una nueva
```

En el menú, **escribe los números** de las máquinas que quieres encender: `2`, `1 3`, `1-4` o `a` para todas. Cada una abre su ventana. Si ya estaba encendida, solo vuelve a abrir la ventana. Antes de encender, `vms` suma la RAM que piden y te avisa si no te alcanza.

```
    #    Nombre                 Sistema     RAM  CPU  Notas
    1 ○  fedora41               Linux        4G    2
    2 ●  ubuntu24               Linux        4G    2  192.168.122.50
    3 ●  win11                  Windows      8G    4  192.168.122.51
    4 ○  macos-sonoma           macOS        8G    4  quickemu
```

| Opción | Acción |
|--------|--------|
| números | Encender y abrir una o varias |
| n | Nueva máquina: Linux, Windows o macOS |
| v | Volver a abrir la ventana de una encendida |
| p / x | Apagar (limpio) / forzar apagado, una o varias |
| c | Clonar: **rápido** (enlazado, instantáneo y casi sin espacio) o completo |
| s | Puntos de restauración: crear, volver a uno, borrar |
| e | Cambiar RAM y CPU |
| b | Borrar máquina (solo sus discos; las ISOs no se tocan) |

### Cómo crea cada sistema

- **Linux**: cualquier ISO. UEFI, disco y red virtio, pantalla SPICE. Detecta la distro de la ISO.
- **Windows 10/11**: UEFI; en Windows 11 también Secure Boot y TPM 2.0, así el instalador no se queja. El disco va en SATA y la red en e1000e para que el instalador los vea sin drivers. Si tienes `virtio-win.iso`, se monta como segundo CD para instalar las *guest tools* (resolución y copiar/pegar). Cuando la ventana diga *"Press any key to boot from CD"*, presiona una tecla rápido.
- **macOS**: usa [quickemu](https://github.com/quickemu-project/quickemu), que baja la imagen de recuperación directo de Apple y prepara OpenCore. Las máquinas viven en `~/VMs`. La licencia de Apple solo permite macOS en hardware Apple, así que úsalo bajo tu responsabilidad. En CPUs AMD algunas versiones pueden fallar.

Las ISOs se buscan en `~/VMs`, `~/Descargas` y `~/Downloads`. Con `quickemu` instalado puedes elegir **d) Descargar** y `quickget` baja la ISO de la distro o de Windows por ti. La ISO se copia una sola vez a `/var/lib/libvirt/images` y se reutiliza.

### Clones rápidos y puntos de restauración

- **Clon rápido**: el disco de la original se convierte en una base de solo lectura (en `/var/lib/libvirt/images/bases`), y la original y el clon escriben cada una en su propia capa encima. El clon sale al instante y las dos pueden usarse sin dañarse entre sí. Cuando borras la última máquina que usa una base, `vms` te ofrece borrarla.
- **Puntos de restauración**: se crean con la máquina apagada. Ideales para "instalo algo, pruebo y regreso a como estaba".
- En clones de Linux, cambia el machine-id para que no peleen por la misma IP: `sudo rm /etc/machine-id && sudo systemd-machine-id-setup`.

## Configuración

`~/.config/eve-ng-manager/config`:

```bash
VM="eve-ng"              # nombre de la VM en libvirt
CONN="qemu:///system"
EVE_USER="root"
FALLBACK_IP=""           # solo si la IP no se detecta sola
VMS_DIR="$HOME/VMs"      # descargas de quickget y máquinas macOS
VMS_SHOW_EVE=0           # 1 = mostrar la VM de EVE-NG en vms
```

## Nombres de imágenes

EVE-NG necesita nombres de carpeta y disco exactos (por ejemplo `vios-15.9/virtioa.qcow2`). `eve` sugiere el nombre correcto para los equipos más comunes, pero si una imagen no arranca, revisa la tabla de imágenes soportadas en la documentación oficial de EVE-NG.

## Problemas comunes

| Problema | Solución |
|----------|----------|
| `eve: command not found` | Abre una terminal nueva o `source ~/.zshrc` |
| Te pide `sudo` para todo | Cierra sesión y vuelve a entrar (grupo `libvirt`) |
| Nodos muy lentos | `./setup.sh --check` y revisa la virtualización anidada; reinicia la PC |
| La red `default` no arranca | Instala `iptables-nft` o `nftables` (wiki de Arch sobre libvirt) |
| La imagen no aparece en EVE-NG | Revisa el nombre de carpeta/disco; usa la opción 5 de `eve` |
| Windows 11 no crea la VM (error de firmware/TPM) | `./setup.sh` opción 2 para instalar `edk2-ovmf` y `swtpm` |
| Windows arranca a una pantalla de UEFI | Se pasó el "Press any key": `virsh -c qemu:///system reset NOMBRE` y presiona una tecla |
| `vms` no ofrece descargar ISOs ni macOS | Instala quickemu: `./setup.sh` opción 8 |

## Desinstalar

```bash
./setup.sh --uninstall
# las máquinas de prueba se borran desde vms (opción b)
# y si quieres borrar también la VM de EVE-NG:
virsh -c qemu:///system undefine eve-ng --remove-all-storage
```

## Licencia

MIT
