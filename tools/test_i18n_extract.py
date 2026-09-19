#!/usr/bin/env python3
"""
tools/test_i18n_extract.py
Unit tests for i18n_extract.py.
Tests string extraction, exclusion rules, f-strings/formatting, merge behavior, and path exclusions.
"""

import sys
import unittest
import tempfile
import csv
from pathlib import Path

# Add tools directory to sys.path to import i18n_extract
TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import i18n_extract

class TestI18nExtract(unittest.TestCase):

    def test_should_exclude(self):
        self.assertTrue(i18n_extract.should_exclude("a"))
        self.assertTrue(i18n_extract.should_exclude(""))
        self.assertTrue(i18n_extract.should_exclude("res://assets/image.png"))
        self.assertTrue(i18n_extract.should_exclude("user://settings.cfg"))
        self.assertTrue(i18n_extract.should_exclude("core_v2/ui/OptionsMenu.gd"))
        self.assertTrue(i18n_extract.should_exclude("icon.png"))
        self.assertTrue(i18n_extract.should_exclude("100%"))
        self.assertTrue(i18n_extract.should_exclude("1280x720"))

        self.assertFalse(i18n_extract.should_exclude("NUEVA PARTIDA"))
        self.assertFalse(i18n_extract.should_exclude("Presiona %s o ESC para cerrar"))
        self.assertFalse(i18n_extract.should_exclude("Idioma"))

    def test_scan_gd_file(self):
        with tempfile.NamedTemporaryFile(mode='w+', suffix='.gd', delete=False) as f:
            f.write('''
extends Node

# This is a comment: text = "Ignored comment"
func _ready():
    print("Log string should be ignored")
    push_error("Error log ignored")
    label.text = "NUEVA PARTIDA"
    dialog.dialog_text = "Presiona %s o ESC para cerrar" % key
    var path = "res://scenes/Menu.tscn"
    var translated = tr("CARGAR PARTIDA")
    var ts_tr = TranslationServer.tr("OPCIONES")
''')
            f_path = Path(f.name)

        try:
            strings = i18n_extract.scan_gd_file(f_path)
            self.assertIn("NUEVA PARTIDA", strings)
            self.assertIn("Presiona %s o ESC para cerrar", strings)
            self.assertIn("CARGAR PARTIDA", strings)
            self.assertIn("OPCIONES", strings)

            self.assertNotIn("Ignored comment", strings)
            self.assertNotIn("Log string should be ignored", strings)
            self.assertNotIn("Error log ignored", strings)
            self.assertNotIn("res://scenes/Menu.tscn", strings)
        finally:
            f_path.unlink()

    def test_scan_tscn_file(self):
        with tempfile.NamedTemporaryFile(mode='w+', suffix='.tscn', delete=False) as f:
            f.write('''
[node name="Label" type="Label" parent="."]
text = "CONFIGURACIÓN"
align = 1

[node name="Button" type="Button" parent="."]
text = "VOLVER"
hint_tooltip = "Regresar al menú principal"
''')
            f_path = Path(f.name)

        try:
            strings = i18n_extract.scan_tscn_file(f_path)
            self.assertIn("CONFIGURACIÓN", strings)
            self.assertIn("VOLVER", strings)
            self.assertIn("Regresar al menú principal", strings)
        finally:
            f_path.unlink()

    def test_merge_csv(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            csv_path = Path(tmp_dir) / "ui_strings.csv"
            header = ["keys", "es", "en"]

            # 1. Initial write
            initial_map = {
                "NUEVA PARTIDA": ["NUEVA PARTIDA", "NUEVA PARTIDA", "NEW GAME"],
                "VIEJA CLAVE": ["VIEJA CLAVE", "VIEJA CLAVE", "OLD KEY"],
            }
            i18n_extract.save_csv(csv_path, header, initial_map)

            # 2. Existing map load
            _, existing = i18n_extract.load_existing_csv(csv_path)
            self.assertEqual(existing["NUEVA PARTIDA"][2], "NEW GAME")

            # 3. Simulate new scan: "NUEVA PARTIDA" present, "OPCIONES" new, "VIEJA CLAVE" orphan
            extracted = {"NUEVA PARTIDA", "OPCIONES"}
            merged = {}
            for k in extracted:
                merged[k] = existing.get(k, [k, k, ""])
            for k, row in existing.items():
                if k not in extracted:
                    merged[k] = row

            i18n_extract.save_csv(csv_path, header, merged)

            # Verify saved CSV
            _, reloaded = i18n_extract.load_existing_csv(csv_path)
            self.assertEqual(reloaded["NUEVA PARTIDA"][2], "NEW GAME")
            self.assertEqual(reloaded["OPCIONES"][2], "")
            self.assertEqual(reloaded["VIEJA CLAVE"][2], "OLD KEY")

    def test_extra_locale_columns_survive(self):
        """A hand-written locale column must not be wiped by a re-extraction."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            csv_path = Path(tmp_dir) / "ui_strings.csv"
            csv_path.write_text(
                "keys,es,en,ko\n"
                "NUEVA PARTIDA,NUEVA PARTIDA,NEW GAME,\uc0c8 \uac8c\uc784\n"
                "SALIR,SALIR,QUIT,\ub098\uac00\uae30\n",
                encoding="utf-8",
            )

            header, existing = i18n_extract.load_existing_csv(csv_path)
            self.assertEqual(header, ["keys", "es", "en", "ko"])

            # A new key shows up; the old ones keep their Korean.
            merged = dict(existing)
            merged["OPCIONES"] = ["OPCIONES", "OPCIONES", "", ""]
            i18n_extract.save_csv(csv_path, header, merged)

            header2, reloaded = i18n_extract.load_existing_csv(csv_path)
            self.assertEqual(header2, ["keys", "es", "en", "ko"])
            self.assertEqual(reloaded["NUEVA PARTIDA"][3], "\uc0c8 \uac8c\uc784")
            self.assertEqual(reloaded["SALIR"][3], "\ub098\uac00\uae30")
            self.assertEqual(reloaded["OPCIONES"][3], "")

    def test_three_column_output_unchanged(self):
        """Regression guard for FD-303: a 3-column CSV round-trips byte for byte."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            csv_path = Path(tmp_dir) / "ui_strings.csv"
            original = "keys,es,en\nNUEVA PARTIDA,NUEVA PARTIDA,NEW GAME\nSALIR,SALIR,QUIT\n"
            csv_path.write_text(original, encoding="utf-8")

            header, existing = i18n_extract.load_existing_csv(csv_path)
            i18n_extract.save_csv(csv_path, header, existing)

            self.assertEqual(csv_path.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
