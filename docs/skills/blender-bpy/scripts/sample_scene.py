import bpy
from odisea_lib import mat_brushed_steel_light, mat_interactable_cyan, apply_mat

NAME = "SampleValve"


def build():
    # cuerpo de la válvula: cilindro
    bpy.ops.mesh.primitive_cylinder_add(radius=0.3, depth=0.5, location=(0, 0, 0))
    body = bpy.context.active_object
    body.name = "ValveBody"
    apply_mat(body, mat_brushed_steel_light())

    # volante: toro
    bpy.ops.mesh.primitive_torus_add(major_radius=0.35, minor_radius=0.06,
                                     location=(0, 0, 0.3))
    wheel = bpy.context.active_object
    wheel.name = "ValveWheel"
    apply_mat(wheel, mat_interactable_cyan())
