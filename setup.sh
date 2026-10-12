#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  setup.sh — Instalador interactivo de EVE-NG sobre QEMU/KVM
#  (libvirt) para Arch Linux.
#
#  Instala y configura todo lo necesario, crea la VM de EVE-NG
#  a partir de la ISO que tú descargues e instala el comando 'eve'.
#
#    ./setup.sh               menú interactivo
#    ./setup.sh --all         instalación completa sin menú
#    ./setup.sh --check       solo diagnóstico
#    ./setup.sh --uninstall   quita el comando 'eve'
# ──────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/eve-ng-manager"
CONF_FILE="$CONF_DIR/config"
IMG_DIR="/var/lib/libvirt/images"
CONN="qemu:///system"
VM="eve-ng"
# shellcheck source=/dev/null
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

PKGS=(libvirt virt-install virt-manager virt-viewer dnsmasq openssh rsync xdg-utils)

NEED_RELOGIN=0
NEED_REBOOT=0

# ── Colores y mensajes ───────────────────────────────────────
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; M=$'\e[35m'; C=$'\e[36m'
D=$'\e[2m'; BD=$'\e[1m'; N=$'\e[0m'
info(){ echo "${C}➜${N} $*"; }
ok()  { echo "${G}✔${N} $*"; }
warn(){ echo "${Y}⚠${N} $*"; }
err() { echo "${R}✘${N} $*" >&2; }
title(){ echo; echo "${M}${BD}━━ $* ━━${N}"; }
ask(){ local c; read -r -p "$1 [S/n]: " c; [[ ! "$c" =~ ^[nN]$ ]]; }
pause(){ read -r -p "${D}Enter para continuar...${N}" _; }

vsh(){ sudo env LC_ALL=C virsh -c "$CONN" "$@"; }

set_conf(){ # set_conf CLAVE valor
  mkdir -p "$CONF_DIR"; touch "$CONF_FILE"
  if grep -q "^$1=" "$CONF_FILE"; then sed -i "s|^$1=.*|$1=\"$2\"|" "$CONF_FILE"
  else echo "$1=\"$2\"" >> "$CONF_FILE"; fi
}

# ── Comprobaciones iniciales ─────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  err "No lo ejecutes como root. El script usa sudo solo cuando hace falta."; exit 1
fi
if ! command -v pacman &>/dev/null; then
  err "Este instalador es para Arch Linux (y derivadas con pacman)."; exit 1
fi

CPU_VENDOR=""
detect_cpu(){
  if grep -qw svm /proc/cpuinfo; then CPU_VENDOR=amd
  elif grep -qw vmx /proc/cpuinfo; then CPU_VENDOR=intel
  else CPU_VENDOR=""; fi
}
nested_on(){
  local f="/sys/module/kvm_$CPU_VENDOR/parameters/nested"
  [[ -f "$f" && "$(cat "$f")" =~ ^(1|Y)$ ]]
}

# ── Pasos ────────────────────────────────────────────────────
step_cpu(){
  title "1. Revisando tu procesador"
  detect_cpu
  if [[ -z "$CPU_VENDOR" ]]; then
    err "Tu CPU no muestra soporte de virtualización."
    info "Entra a la BIOS/UEFI y activa ${BD}SVM / AMD-V${N} (AMD) o ${BD}VT-x${N} (Intel), luego vuelve a intentar."
    return 1
  fi
  ok "Virtualización soportada (${CPU_VENDOR^^})"
}

step_packages(){
  title "2. Instalando QEMU, libvirt y herramientas"
  local pk=("${PKGS[@]}") missing=() p
  if pacman -Qq qemu-full &>/dev/null || pacman -Qq qemu-desktop &>/dev/null; then
    ok "QEMU ya está instalado"
  else
    pk+=(qemu-desktop)
  fi
  for p in "${pk[@]}"; do pacman -Qq "$p" &>/dev/null || missing+=("$p"); done
  if (( ! ${#missing[@]} )); then ok "Todos los paquetes ya están instalados"; return 0; fi
  info "Se instalarán: ${BD}${missing[*]}${N}"
  info "En Arch se recomienda actualizar el sistema al instalar, por eso se usa 'pacman -Syu'."
  ask "¿Continuar?" || return 1
  sudo pacman -Syu --needed "${missing[@]}" && ok "Paquetes instalados"
}

step_services(){
  title "3. Activando el servicio libvirt"
  if sudo systemctl enable --now libvirtd.service &>/dev/null; then
    ok "libvirtd activo y habilitado al arranque"
  else
    err "No se pudo iniciar libvirtd. Revisa: systemctl status libvirtd"; return 1
  fi
  if id -nG "$USER" | grep -qw libvirt; then
    ok "Tu usuario ya está en el grupo libvirt"
  else
    sudo usermod -aG libvirt "$USER" && ok "Usuario agregado al grupo libvirt"
    NEED_RELOGIN=1
  fi
}

step_network(){
  title "4. Configurando la red virtual"
  if ! vsh net-info default &>/dev/null; then
    warn "No existe la red 'default', la creo"
    vsh net-define /usr/share/libvirt/networks/default.xml >/dev/null || { err "No se pudo crear la red"; return 1; }
  fi
  if vsh net-info default | grep -qE 'Active:\s+yes'; then
    ok "Red 'default' activa"
  elif vsh net-start default >/dev/null; then
    ok "Red 'default' iniciada"
  else
    err "No se pudo iniciar la red 'default'."
    info "En Arch esto suele resolverse instalando ${BD}iptables-nft${N} o ${BD}nftables${N} (ver la wiki de libvirt)."
    return 1
  fi
  vsh net-autostart default >/dev/null && ok "La red arrancará sola al iniciar"
}

step_nested(){
  title "5. Virtualización anidada"
  info "Permite que los routers y equipos dentro de EVE-NG usen aceleración."
  detect_cpu; [[ -n "$CPU_VENDOR" ]] || return 1
  local mod="kvm_$CPU_VENDOR"
  if nested_on; then ok "Ya está activa"; return 0; fi
  echo "options $mod nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf >/dev/null
  ok "Configuración guardada en /etc/modprobe.d/kvm-nested.conf"
  if [[ -z "$(vsh list --name 2>/dev/null | tr -d '[:space:]')" ]]; then
    sudo modprobe -r "$mod" 2>/dev/null && sudo modprobe "$mod" 2>/dev/null
  fi
  if nested_on; then ok "Activada"
  else warn "Se activará cuando reinicies la PC"; NEED_REBOOT=1; fi
}

step_cli(){
  title "6. Instalando el comando 'eve'"
  mkdir -p "$BIN_DIR"
  install -m 755 "$HERE/eve" "$BIN_DIR/eve" && ok "Instalado en $BIN_DIR/eve"
  mkdir -p "$CONF_DIR"
  [[ -f "$CONF_FILE" ]] || { cp "$HERE/config.example" "$CONF_FILE"; ok "Configuración creada en $CONF_FILE"; }
  case ":$PATH:" in
    *":$BIN_DIR:"*) ok "$BIN_DIR ya está en tu PATH" ;;
    *)
      local rc="$HOME/.bashrc"; [[ "${SHELL:-}" == *zsh ]] && rc="$HOME/.zshrc"
      grep -q '.local/bin' "$rc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
      warn "Agregué ~/.local/bin al PATH en $rc (abre una terminal nueva)"
      ;;
  esac
}

pick_iso(){
  local found=() i c f
  mapfile -t found < <(find "$HOME/Descargas" "$HOME/Downloads" "$HOME" -maxdepth 2 \
                        -iname '*eve*.iso' 2>/dev/null | sort -u)
  if (( ${#found[@]} )); then
    echo "ISOs de EVE-NG encontradas:" >&2
    for i in "${!found[@]}"; do printf "  %d) %s\n" $((i+1)) "${found[i]}" >&2; done
    echo "  o) Otra ruta" >&2
    read -r -p "> " c
    if [[ "$c" =~ ^[0-9]+$ ]] && (( c>=1 && c<=${#found[@]} )); then echo "${found[c-1]}"; return 0; fi
  fi
  read -e -r -p "Ruta de la ISO (Tab autocompleta, o arrástrala aquí): " f
  f="${f#file://}"; f="${f//%20/ }"; f="${f//\\ / }"; f="${f//\'/}"; f="${f//\"/}"
  f="${f%"${f##*[![:space:]]}"}"; f="${f#"${f%%[![:space:]]*}"}"; f="${f/#\~/$HOME}"
  [[ -f "$f" ]] || { err "No existe: $f"; return 1; }
  echo "$f"
}

cdrom_target(){ vsh domblklist "$VM" --details 2>/dev/null | awk '$2=="cdrom"{print $3; exit}'; }

step_vm(){
  title "7. Crear la VM de EVE-NG"
  if vsh dominfo "$VM" &>/dev/null; then
    ok "Ya existe una VM llamada '$VM'"
    if vsh dumpxml "$VM" | grep -q "host-passthrough"; then
      ok "Usa el CPU del host (host-passthrough)"
    else
      warn "La VM no usa host-passthrough; sin eso la virtualización anidada no llega a EVE-NG."
      if ask "¿Corregirlo ahora? (se aplica en el próximo arranque de la VM)"; then
        sudo virt-xml --connect "$CONN" "$VM" --edit --cpu host-passthrough >/dev/null && ok "Corregido"
      fi
    fi
    return 0
  fi

  cat <<EOF
Necesitas la ISO de ${BD}EVE-NG Community${N} (gratis).
Descárgala desde ${C}https://www.eve-ng.net${N} → sección ${BD}Downloads${N} → EVE-NG Community (ISO).
Este proyecto no la incluye; la descargas tú desde el sitio oficial.

EOF
  local iso; iso=$(pick_iso) || return 1
  ok "ISO: $iso"

  local name total_gb cores sug_ram sug_cpu ram cpus disk avail
  read -r -p "Nombre de la VM [$VM]: " name; VM="${name:-$VM}"
  total_gb=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
  cores=$(nproc)
  sug_ram=$(( total_gb / 2 )); (( sug_ram < 4 )) && sug_ram=4
  sug_cpu=$(( cores / 2 ));    (( sug_cpu < 2 )) && sug_cpu=2
  echo
  info "Tu PC tiene ${BD}${total_gb} GB${N} de RAM y ${BD}${cores}${N} hilos de CPU."
  info "Te sugiero darle la mitad a EVE-NG. Más RAM = más nodos a la vez."
  read -r -p "RAM para EVE-NG en GB [$sug_ram]: " ram;  ram="${ram:-$sug_ram}"
  read -r -p "Núcleos de CPU [$sug_cpu]: " cpus;         cpus="${cpus:-$sug_cpu}"
  read -r -p "Tamaño del disco en GB [100]: " disk;      disk="${disk:-100}"
  [[ "$ram$cpus$disk" =~ ^[0-9]+$ ]] || { err "Solo números, por favor."; return 1; }
  (( ram >= total_gb )) && { err "No puedes darle toda tu RAM."; return 1; }
  (( ram < 6 )) && warn "Con menos de 6 GB vas a poder correr pocos nodos."
  info "El disco es dinámico: solo ocupa lo que realmente uses, no los $disk GB de golpe."
  avail=$(df -BG --output=avail "$IMG_DIR" 2>/dev/null | tail -1 | tr -dc '0-9')
  [[ -n "$avail" ]] && (( avail < 30 )) && warn "Solo tienes ${avail} GB libres en $IMG_DIR."

  echo
  info "Resumen: ${BD}$VM${N} · ${ram} GB RAM · ${cpus} CPU · disco ${disk} GB"
  ask "¿Crear la VM?" || return 1

  local iso_dst="$iso"
  if [[ "$iso" != "$IMG_DIR/"* ]]; then
    iso_dst="$IMG_DIR/$(basename "$iso")"
    info "Copiando la ISO a $IMG_DIR (libvirt no puede leer tu carpeta personal)..."
    sudo cp "$iso" "$iso_dst" || { err "No se pudo copiar la ISO"; return 1; }
  fi

  local osi="detect=on,require=off"
  osinfo-query os short-id=ubuntu22.04 2>/dev/null | grep -q ubuntu22.04 && osi="ubuntu22.04"

  cat <<EOF

${BD}Ahora se abre una ventana con la pantalla de la VM.${N}
  • Si el menú de arranque te deja elegir, escoge la opción para ${BD}VM${N} (no "Bare").
  • La instalación es casi automática y tarda unos minutos.
  • En el primer arranque EVE-NG te hace unas preguntas:
      - Contraseña de root: ${Y}anótala${N}, el comando 'eve' la usará por SSH.
      - Hostname y dominio: puedes dejar los valores por defecto.
      - Red: elige ${BD}dhcp${N}.
      - NTP vacío y proxy "direct".
  • Este script espera aquí hasta que la instalación termine.

EOF
  pause

  virt-viewer --connect "$CONN" --wait --reconnect "$VM" &>/dev/null & disown

  info "Creando la VM e iniciando la instalación..."
  if ! sudo virt-install --connect "$CONN" \
        --name "$VM" \
        --memory $(( ram * 1024 )) \
        --vcpus "$cpus" \
        --cpu host-passthrough \
        --osinfo "$osi" \
        --disk "path=$IMG_DIR/$VM.qcow2,size=$disk,format=qcow2,bus=virtio" \
        --cdrom "$iso_dst" \
        --network network=default,model=virtio \
        --graphics spice \
        --noautoconsole --wait -1; then
    err "Falló la creación de la VM."; return 1
  fi
  set_conf VM "$VM"
  ok "Instalación terminada"

  local t; t=$(cdrom_target)
  if [[ -n "$t" ]]; then
    vsh change-media "$VM" "$t" --eject --config &>/dev/null
    vsh change-media "$VM" "$t" --eject --live   &>/dev/null
    ok "ISO retirada de la VM"
  fi
  if ask "¿Borrar la copia de la ISO en $IMG_DIR para liberar espacio?"; then
    [[ "$iso_dst" != "$iso" ]] && sudo rm -f "$iso_dst" && ok "Borrada"
  fi
  info "Si la ventana del primer arranque no aparece, ábrela con: virt-manager"
}

step_check(){
  title "Diagnóstico"
  local good=0 bad=0
  chk(){ if eval "$2" &>/dev/null; then ok "$1"; ((good++)); else err "$1  ${D}→ $3${N}"; ((bad++)); fi; }
  detect_cpu
  chk "CPU con virtualización"            '[[ -n "$CPU_VENDOR" ]]'                   "actívala en la BIOS"
  chk "QEMU instalado"                    'pacman -Qq qemu-desktop || pacman -Qq qemu-full' "paso 2"
  chk "libvirt instalado"                 'pacman -Qq libvirt'                       "paso 2"
  chk "virt-install instalado"            'pacman -Qq virt-install'                  "paso 2"
  chk "libvirtd activo"                   'systemctl is-active --quiet libvirtd'     "paso 3"
  chk "Grupo libvirt en esta sesión"      'id -nG | grep -qw libvirt'                "cierra sesión y vuelve a entrar"
  chk "Red 'default' activa"              'vsh net-info default | grep -qE "Active:\s+yes"' "paso 4"
  chk "Virtualización anidada"            'nested_on'                                "paso 5 y reiniciar"
  chk "Comando 'eve' instalado"           '[[ -x "$BIN_DIR/eve" ]]'                  "paso 6"
  chk "Comando 'eve' en el PATH"          'command -v eve'                           "abre una terminal nueva"
  chk "VM '$VM' existe"                   'vsh dominfo "$VM"'                        "paso 7"
  chk "VM usa host-passthrough"           'vsh dumpxml "$VM" | grep -q host-passthrough' "paso 7"
  echo
  if (( bad == 0 )); then ok "${BD}Todo listo.${N} Ejecuta: ${G}eve${N}"
  else warn "$good bien, $bad por revisar."; fi
}

summary(){
  echo
  (( NEED_REBOOT ))  && warn "${BD}Reinicia la PC${N} para activar la virtualización anidada."
  (( NEED_RELOGIN && ! NEED_REBOOT )) && warn "${BD}Cierra sesión y vuelve a entrar${N} para que se aplique el grupo libvirt."
  ok "Cuando quieras practicar, solo ejecuta: ${G}${BD}eve${N}"
  info "La web de EVE-NG usa por defecto ${BD}admin / eve${N}. Al entrar elige consola ${BD}HTML5${N}, así no necesitas instalar nada más."
}

full_install(){
  step_cpu      || return 1
  step_packages || return 1
  step_services || return 1
  step_network  || return 1
  step_nested
  step_cli
  step_vm
  summary
}

uninstall(){
  rm -f "$BIN_DIR/eve" && ok "Eliminado $BIN_DIR/eve"
  info "Tu configuración sigue en $CONF_DIR y la VM no se tocó."
  info "Para borrar la VM: virsh -c $CONN undefine $VM --remove-all-storage"
}

menu(){
  while true; do
    clear
    echo "${M}${BD}  ╭──────────────────────────────────────────╮"
    echo "  │      EVE-NG en Arch · Instalador          │"
    echo "  ╰──────────────────────────────────────────╯${N}"
    echo
    echo "  1) ${BD}Instalación completa${N}  ${D}(recomendado, hace todo paso a paso)${N}"
    echo
    echo "  ${D}Pasos sueltos:${N}"
    echo "  2) Instalar QEMU, libvirt y herramientas"
    echo "  3) Activar servicio libvirt y permisos"
    echo "  4) Configurar red virtual"
    echo "  5) Activar virtualización anidada"
    echo "  6) Instalar el comando 'eve'"
    echo "  7) Crear la VM de EVE-NG desde la ISO"
    echo
    echo "  d) Diagnóstico  ${D}(revisa que todo esté bien)${N}"
    echo "  u) Desinstalar el comando 'eve'"
    echo "  0) Salir"
    echo
    read -r -p "  Opción: " op
    case "$op" in
      1) full_install; pause ;;
      2) step_cpu && step_packages; pause ;;
      3) step_services; summary; pause ;;
      4) step_network; pause ;;
      5) step_nested; summary; pause ;;
      6) step_cli; pause ;;
      7) step_cpu && step_vm; pause ;;
      d|D) step_check; pause ;;
      u|U) uninstall; pause ;;
      0|q) exit 0 ;;
    esac
  done
}

case "${1:-}" in
  --all)       full_install ;;
  --check)     step_check ;;
  --uninstall) uninstall ;;
  "")          menu ;;
  *)           echo "Uso: $0 [--all | --check | --uninstall]"; exit 1 ;;
esac
