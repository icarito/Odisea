# Prop: Ascensor (ElevatorProp)

El `ElevatorProp` es un sistema de transporte vertical altamente modular diseñado bajo los principios de **Odisea Logic Circuit System (OLCS)**. En lugar de configuraciones manuales complejas, su funcionamiento se deriva de su estructura jerárquica en la escena.

## Estructura Jerárquica

El ascensor se organiza en tres componentes principales:

1.  **ElevatorProp (Raíz)**: Contiene el script `ElevatorController.gd`.
2.  **Platform (Plataforma)**: El cuerpo físico que se desplaza. Contiene los botones internos.
3.  **Floors (Pisos)**: Un nodo contenedor que agrupa todos los niveles a los que el ascensor puede viajar.

### Los Nodos de Piso (`FloorX`)
Cada piso es un nodo espacial hijo de `Floors`. Su **posición global en Y** determina exactamente la altura de parada de la plataforma.
- Para cambiar la altura de un piso, simplemente mueve el nodo `Floor0`, `Floor1`, etc., en el eje Y dentro del editor de Godot.

## Sistema de Lógica y Llamado

### Auto-Conexión (Auto-Wiring)
El ascensor utiliza el sistema de auto-conexión de `PropBaseV2`. 
- Si colocas un `PedestalButton` (o cualquier switch) como **hijo directo** de un `ElevatorLogicInput`, el sistema los vinculará automáticamente sin necesidad de cables manuales.

### Tipos de Inputs
- **Llamado Externo**: Cada nodo `FloorX` contiene un `ElevatorLogicInput` (`Input`) y un `PedestalButton`. Al presionar este botón, el ascensor viaja a la altura de ese nodo específico.
- **Botón Interno (Siguiente Piso)**: Ubicado dentro de la `Platform`, este botón tiene un `floor_index = -1`. Esto le indica al controlador que debe viajar al siguiente piso disponible en orden ascendente (o volver al piso 0 si está en el último).

## Configuración y Atributos

### ElevatorController.gd
- `platform_path`: Ruta al nodo `Platform`.
- `floors_path`: Ruta al nodo contenedor `Floors`.

### ElevatorLogicInput.gd
- `floor_index`: El índice del piso al que pertenece. Si es `-1`, actúa como botón de "Siguiente".

## Cómo añadir un nuevo piso

1.  Abre la escena del ascensor o herédala.
2.  Duplica uno de los nodos de piso (ej: `Floor2`) dentro del contenedor `Floors`.
3.  Renombra el nuevo nodo (ej: `Floor3`).
4.  Selecciona el nodo `Input` dentro de ese piso y cambia su `floor_index` a `3`.
5.  Mueve el nodo `Floor3` a la altura deseada en el eje Y.
6.  *El controlador detectará automáticamente el nuevo piso al iniciar la escena.*

## Validación y Pruebas

Este prop está integrado en el [Pipeline de Desarrollo de Props](props_pipeline.md). Para verificar cambios visuales o de lógica sin entrar al juego completo:

1.  Asegúrate de estar en la raíz del proyecto.
2.  Ejecuta el runner de validación:
    ```bash
    ./test_prop.sh ElevatorProp
    ```
3.  Revisa las capturas generadas en `test_output/props/ElevatorProp_*.png`. Esto confirmará que las animaciones y estados (Idle/Active) responden correctamente.

---
> [!NOTE]
> El sistema es totalmente dinámico. Si mueves un piso en tiempo de ejecución (mediante otro script), el ascensor viajará a la nueva posición Y actualizada.

