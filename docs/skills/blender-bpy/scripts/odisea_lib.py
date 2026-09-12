#!/usr/bin/env python3
"""Paleta de materiales y helpers de Odisea para scene scripts bpy.

Uso dentro de un scene script:

    import sys
    sys.path.insert(0, ".claude/skills/blender-bpy/scripts")
    from odisea_lib import mat_brushed_steel, mat_interactable_cyan

Convenciones tomadas de docs/agents/tooling.md (sección de materiales inline).
"""
import bpy


def _principled(name, base=(0.5, 0.5, 0.5), metallic=0.0, roughness=0.5,
                emission=None, emission_strength=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def mat_brushed_steel_light():
    return _principled("M_BrushedSteelLight", base=(0.42, 0.44, 0.46),
                       metallic=1.0, roughness=0.18)


def mat_brushed_steel_dark():
    return _principled("M_BrushedSteelDark", base=(0.30, 0.32, 0.34),
                       metallic=1.0, roughness=0.30)


def mat_interactable_cyan():
    return _principled("M_InteractableCyan", base=(0.15, 0.80, 0.78),
                       metallic=0.0, roughness=0.3,
                       emission=(0.0, 0.55, 0.52), emission_strength=1.0)


def mat_warning_yellow():
    return _principled("M_WarningYellow", base=(0.85, 0.68, 0.08),
                       metallic=0.0, roughness=0.6)


def mat_matte_plastic(name="M_Plastic", base=(0.5, 0.5, 0.5), roughness=0.7):
    return _principled(name, base=base, metallic=0.0, roughness=roughness)


def apply_mat(obj, mat):
    if obj.data and hasattr(obj.data, "materials"):
        if obj.data.materials:
            obj.data.materials[0] = mat
        else:
            obj.data.materials.append(mat)


def orient_godot(obj):
    """Godot 3 importa glTF con +Y up; aplicar -90° en X para alinear ejes
    si el modelado asume Z-up. Ajustar según el asset real."""
    import math
    obj.rotation_euler[0] = -math.pi / 2
