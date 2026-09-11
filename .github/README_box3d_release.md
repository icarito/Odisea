# `.github/box3d_release`

La release de [icarito/godot-box3d-3](https://github.com/icarito/godot-box3d-3) de la que
sale el runtime en CI. **Un solo lugar**: estaba pinneada por separado en cada workflow y
habia derivado a tres valores distintos (`v0.2.0` en determinism, `v0.2.2` en export, y
Godot 3.6.2 **stock** en los tests), asi que los tests corrian contra un motor que no es el
que se envia.

El binario stock de godotengine **no trae el modulo Box3D**: el proyecto declara
`3d/physics_engine="Box3D"` y con el stock cae a Bullet en silencio, sin avisar. Tampoco
conoce las settings del fork, y al abrir el proyecto las borra de `project.godot`.

Al cortar una release nueva del fork, cambiar este archivo y nada mas.
