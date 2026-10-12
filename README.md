# eve-ng-manager

Instala y gestiona **EVE-NG** en **Arch Linux** usando **QEMU/KVM + libvirt**, desde cero y sin complicaciones.

- **`setup.sh`** instala todo lo necesario, configura el sistema y crea la VM de EVE-NG a partir de la ISO que tú descargues.
- **`eve`** es el comando del día a día: enciende EVE-NG, abre la web y te deja subir imágenes mientras practicas.

## Inicio rápido

```bash
git clone https://github.com/TU_USUARIO/eve-ng-manager.git
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
| 2 | Instala `qemu-desktop`, `libvirt`, `virt-install`, `virt-manager`, `virt-viewer`, `dnsmasq`, `openssh`, `rsync`, `xdg-utils` |
| 3 | Activa `libvirtd` y te agrega al grupo `libvirt` |
| 4 | Activa la red virtual `default` (NAT + DHCP) |
| 5 | Activa la virtualización anidada (para que los nodos de EVE-NG vayan rápido) |
| 6 | Instala el comando `eve` en `~/.local/bin` |
| 7 | Crea la VM de EVE-NG con la ISO, sugiriendo RAM y CPU según tu PC |

Puedes ejecutar cada paso por separado desde el menú. Si ya tenías algo instalado, lo detecta y lo salta.

Opciones sin menú:

```bash
./setup.sh --all        # instalación completa
./setup.sh --check      # diagnóstico: revisa que todo esté bien
./setup.sh --uninstall  # quita el comando 'eve' (no toca la VM)
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
| 0 | Salir (pregunta si apagar la VM) |

Para elegir un archivo puedes escribir la ruta (Tab autocompleta) o arrastrarlo a la terminal. Después de cada subida se arreglan los permisos de EVE-NG automáticamente.

Si la VM se apaga mientras `eve` está abierto, el script lo detecta y se cierra.

### En la web de EVE-NG

- Usuario por defecto: `admin` / `eve`.
- Al iniciar sesión elige consola **HTML5**: así abres los equipos desde el navegador sin instalar nada más.

## Configuración

`~/.config/eve-ng-manager/config`:

```bash
VM="eve-ng"              # nombre de la VM en libvirt
CONN="qemu:///system"
EVE_USER="root"
FALLBACK_IP=""           # solo si la IP no se detecta sola
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

## Desinstalar

```bash
./setup.sh --uninstall
# y si quieres borrar también la VM:
virsh -c qemu:///system undefine eve-ng --remove-all-storage
```

## Licencia

MIT
