Efecto *campo de estrellas*
===========================

En este proyecto se implementa un campo de estrellas vertical.

Por desgracia no he incluido las versiones anteriores en git para
poder ver su evolución. A continuación incluyo un resumen:


Versión original
----------------

En la versión original cada estrella se representa con:

.. code-block:: c

   typedef struct {
       u8 x;
       u8 y;
   } TStar;

El programa almacena las estrellas en un array bidimensional:

.. code-block:: c

   TStar stars[NUM_LAYERS][NUM_STARS];

Los layers representan la profundidad de la estrella y determinan su
velocidad: mas lento cuanto mas lejos.

Se definen tres funciones responsables de inicializar las estrellas,
pintarlas y moverlas:

.. code-block:: c

   // assigna coordenadas aleatorias a las estrellas
   void field_init(void);

   // dibuja las estrellas. Pasando el color 0 las borra.
   void field_draw(u8 color);

   // desplaza las estrellas. Si sobrepasan el límite de la pantalla
   // las mete nuevamente por la parte de arriba.
   void field_update(void);

Funciona pero con mucho parpadeo.


Primera iteración
-----------------

Al dibujar/borrar las estrellas se calcula la dirección de la memoria
de vídeo de cada estrella utilizando la funcion ``cpct_getScreenPtr``.
Esto requiere calcular multiplicaciones, divisiones y módulos, cosas
que el Z80 no puede hacer directamente y hay que hacer por software.

Para paliarlo se precalcula una tabla (``line_pointers``) de 200
entradas que almacena la dirección de inicio de cada línea de la
memoria de vídeo. Para calcular la dirección de memoria en la que hay
que pintar la estrella ``s`` es suficiente con hacer:

.. code-block:: c

   p = line_pointers[s->y] + s->x

Se observa una mejora importante en los FPS. El consumo de memoria es
relativamente grande (800 bytes) pero puede ser aceptable.


Segunda iteración
-----------------

En esta iteración se eliminan los layers, la tabla de estrellas pasa a
ser lineal. La velocidad y el color se almacenan en la propia
estrella:

.. code-block:: c

   typedef struct {
       u8 x;
       u8 y;
       u8 s;
       u8 c;
   } TStar;

Este cambio no supone una mejora de rendimiento pero permite
simplificar el código, eliminado los dobles bucles.


Tercera iteración
-----------------

Se observa que ahora la estructura de las funciones de pintar/borrar y
actualiza es la misma: un bucle que recorre la lista de estrellas y
hace algo con cada una de ellas.

Se fusionan las tres operaciones en una única función ``field_do``.
Esto permite utilizar un único bucle, reduciendo el número de
indexaciones que hay que hacer de la tabla de estrellas y generando
código ensamblador mas compacto.

Que esto supusiera una mejora de rendimiento importante me sorprendio.
Tiene sentido, pero habria que hacer alguna prueba mas para
confirmarlo.


Cuarta iteración
----------------

Se realizan pequeños cambios que mejoran el rendimiento marginalmente.
Estoy ya es *vicio*.

- la función ``cpct_rand`` es relativamente costosa, se reduce el
  número de llamadas.

  El truco es que no es necesario generar N números aleatorios, es
  suficiente (mas o menos) con uno a partir del que derivan el resto.
  Es resultado probablemente sea menos aleatorio pero no se aprecia
  mientas no se abuse.

- el operador ``%`` es costoso, sdcc lo implementa por software.
  Normalmente se utiliza junto con ``cpct_rand`` para obtener valores
  aleatorios en cierto rango.

  En la función ``field_do`` se sustituye el operador ``%`` por una
  expresión *similar* que utiliza el operador ``&``:

  .. code-block:: c

     x = cpct_rand() % 80;

  se sustituye por:

  .. code-block:: c

     r = cpct_rand()
     x = (r & 63) + (r & 15);

  La nueva expresión genera un valor diferente, pero igualmente
  aleatorio y casi en el mismo rango, con lo que a efectos pràcticos
  es equivalente y resulta mas rápida de calcular.
