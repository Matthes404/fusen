#!/usr/bin/env bash
# Packt den fertigen Linux-Build als .deb für Debian, Ubuntu und Mint.
#
#   linux/packaging/build_deb.sh <version> [bundle] [ziel.deb]
#
#   <version>  etwa 0.2.0 oder 0.2.0-dev.14
#   [bundle]   Standard: build/linux/x64/release/bundle
#   [ziel.deb] Standard: build/linux/fusen-<version>-linux-amd64.deb
#
# Das Programm landet unter /opt/fusen, dazu ein Link /usr/bin/fusen, ein
# Starter fürs Menü und die Symbole. GTK und keybinder kommen als
# Abhängigkeiten aus den Paketquellen, statt beizuliegen – so hält die
# Paketverwaltung sie aktuell.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$here/../.." && pwd)"

version="${1:?Version fehlt, etwa 0.2.0}"
bundle="${2:-$app/build/linux/x64/release/bundle}"
out="${3:-$app/build/linux/fusen-$version-linux-amd64.deb}"
arch="${DEB_ARCH:-amd64}"

if [[ ! -x "$bundle/fusen" ]]; then
  echo "Kein Build unter $bundle – erst 'flutter build linux --release'." >&2
  exit 1
fi

# 0.2.0-dev.14 wird zu 0.2.0~dev.14: die Tilde sortiert einen
# Entwicklungsstand vor das fertige Release, sodass 0.2.0 ihn ersetzt.
deb_version="${version//-/\~}"

# Die neueste glibc-Version, die der Build verlangt. Ohne diese Angabe ließe
# sich das Paket auf einem älteren System installieren und bräche erst beim
# Start ab. libdartjni gehört zu einem Android-Plugin und wird unter Linux
# nie geladen.
glibc="$(
  find "$bundle" -type f \( -name '*.so' -o -name fusen \) \
    ! -name libdartjni.so -exec objdump -T {} + 2>/dev/null |
    grep -o 'GLIBC_[0-9.]*' | sed 's/^GLIBC_//' | sort -Vu | tail -n 1
)" || true

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

install -d "$root/opt/fusen" "$root/usr/bin" "$root/DEBIAN" \
  "$root/usr/share/applications" "$root/usr/share/doc/fusen"
cp -a "$bundle/." "$root/opt/fusen/"
ln -s /opt/fusen/fusen "$root/usr/bin/fusen"

install -m 644 "$here/dev.fusen.fusen.desktop" "$root/usr/share/applications/"
for icon in "$here"/icons/hicolor/*/apps/dev.fusen.fusen.png; do
  size="$(basename "$(dirname "$(dirname "$icon")")")"
  install -D -m 644 "$icon" "$root/usr/share/icons/hicolor/$size/apps/dev.fusen.fusen.png"
done
install -m 644 "$app/../LICENSE" "$root/usr/share/doc/fusen/copyright"

# Einheitliche Rechte, egal mit welcher umask gebaut wurde.
find "$root" -type d -exec chmod 755 {} +
find "$root/opt/fusen" -type f -exec chmod 644 {} +
chmod 755 "$root/opt/fusen/fusen"

cat > "$root/DEBIAN/control" <<EOF
Package: fusen
Version: $deb_version
Section: utils
Priority: optional
Architecture: $arch
Maintainer: the Fusen contributors <https://github.com/Matthes404/fusen/issues>
Homepage: https://github.com/Matthes404/fusen
Installed-Size: $(du -sk --exclude=DEBIAN "$root" | cut -f1)
Depends: libc6 (>= ${glibc:-2.31}), libgtk-3-0t64 | libgtk-3-0, libkeybinder-3.0-0, libepoxy0, libstdc++6
Description: Haftnotizen, sortiert nach Projekt
 Fusen ist ein digitaler Stapel Haftnotizen: Gedanken, Schritte, Fragen und
 Anweisungen landen als Zettel in ihrem Projekt. Die Daten liegen lokal und
 lassen sich optional über einen eigenen Server zwischen Geräten abgleichen.
EOF

mkdir -p "$(dirname "$out")"
dpkg-deb --build --root-owner-group -Zxz "$root" "$out" > /dev/null
echo "$out"
