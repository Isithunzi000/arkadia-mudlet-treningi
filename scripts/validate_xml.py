#!/usr/bin/env python3
"""Bramka well-formedness XML pakietu Mudleta (parser expat).

Blad parsowania -> komunikat z numerem linii i kolumny + exit 1.
Wywolywana z:
- validate.yml (push/PR),
- release.yml (przed budowa paczki),
- build_mpackage.py (przed zipem; import validate_xml_bytes).

Bez argumentow waliduje glowny XML pakietu (XML_NAME z build_mpackage.py).

Uzycie: python3 scripts/validate_xml.py [plik.xml]
"""
import os
import sys
import xml.dom.minidom
from xml.parsers.expat import ExpatError


def validate_xml_bytes(xml_bytes, label):
    """Parsuje XML; przy bledzie wypisuje linie/kolumne i przerywa (exit 1)."""
    try:
        xml.dom.minidom.parseString(xml_bytes)
    except ExpatError as e:
        raise SystemExit(
            "BLAD: %s nie jest poprawnym XML (linia %d, kolumna %d): %s"
            % (label, e.lineno, e.offset, e)
        )


def main():
    if len(sys.argv) > 2:
        raise SystemExit(__doc__)
    if len(sys.argv) == 2:
        path = sys.argv[1]
    else:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import build_mpackage

        path = os.path.join(build_mpackage.ROOT, build_mpackage.XML_NAME)
    with open(path, "rb") as f:
        data = f.read()
    validate_xml_bytes(data, os.path.basename(path))
    print("XML OK: " + os.path.basename(path))


if __name__ == "__main__":
    main()
