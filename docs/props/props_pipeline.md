# Pipeline de Desarrollo de Props (V2)

Este documento describe el flujo de trabajo estandarizado para crear, validar y documentar props interactivos en el proyecto Odisea.

## 1. Clasificación

Es fundamental distinguir entre dos tipos de archivos de escena:

| Tipo | Ubicación | Propósito |
| :--- | :--- | :--- |
| **Prop** | `res://core_v2/props/` | La unidad operativa mínima (el objeto en sí). Ej: `ElevatorProp.tscn`. |
| **Test Scene** | `res://core_v2/tests/` | Un entorno de prueba para integrar uno o más props. Ej: `TestScene_Elevator.tscn`. |

## 2. Principios de Diseño Jerárquico (OCLS)

Para maximizar la autonomía de los props, seguimos estos principios:

### Jerarquía como Lógica
Las propiedades del prop deben inferirse de su estructura de nodos siempre que sea posible. 
- *Ejemplo*: En el ascensor, la altura de los pisos se lee de la posición global `Y` de sus nodos hijos, no de variables estáticas.

### Auto-Wiring (Auto-Conexión)
Los props deben ser "Plug & Play". 
- Si un componente de lógica (como `ElevatorLogicInput`) tiene un botón como hijo directo, el script base `PropBaseV2` los conectará automáticamente mediante señales.
- Esto reduce la dependencia de `LogicCircuitManager` para el funcionamiento interno del prop.

## 3. Validación Visual y Funcional

Para asegurar que un prop funciona correctamente sin necesidad de abrir el motor, utilizamos herramientas de automatización.

### El script `test_prop.sh`
Este comando ejecuta el prop en un entorno controlado (`PropStage.tscn`) y toma capturas de pantalla de sus diferentes estados.

```bash
# Validar un prop específico y generar capturas
./test_prop.sh MiProp
```

**Beneficios**:
- **Delta Check**: La herramienta verifica que haya una diferencia visual significativa entre el estado "Idle" y "Active".
- **Agilidad**: Permite al agente IA (o al desarrollador) confirmar cambios visuales o de animación rápidamente.

### Scripts de Validación OYS
Cada prop puede tener un script `.oys` (Odisea Yield Script) asociado con su mismo nombre (ej: `MiProp.oys`) que define la secuencia de interacción para las pruebas unitarias.

## 4. Documentación de Props

Cada prop nuevo debe documentarse en `docs/props/<nombre_prop>.md`, detallando:
- Su jerarquía interna.
- Qué señales emite o recibe.
- Instrucciones para que otros desarrolladores lo integren en sus niveles.
