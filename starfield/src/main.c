//-----------------------------LICENSE NOTICE------------------------------------
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Lesser General Public License for more details.
//
//  You should have received a copy of the GNU Lesser General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//------------------------------------------------------------------------------

#include <cpctelera.h>
#include <stdio.h>

#define NUM_STARS 24
#define NUM_COLS 80
#define NUM_LINES 200

// definiendo DEBUG se muestra el número de FPS
#undef DEBUG

typedef struct {
    u8 x; /* coordenada x, en bytes */
    u8 y; /* coordenada y, en bytes */
    u8 s; /* velocidad              */
    u8 c; /* color                  */
} TStar;

/* Colores de la paleta:
 * fondo, estrella lenta, intermedia i rápida
 */
const u8 palette[] = {HW_BLACK, HW_YELLOW, HW_PASTEL_YELLOW, HW_BRIGHT_WHITE};
const char hextab[] = "0123456789ABCDEF";

/* line_pointers almacena la dirección de inicio de cada línea de la
 * memoria de vídeo. Evita utilizar cpct_getScreenPtr (costosa en
 * CPU).
 */
u8 *line_pointers[NUM_LINES];

/* Tabla de estrellas.
 */
TStar stars[NUM_STARS];

void field_init(void) {
    TStar *p;
    u8 i;
    u8 r;

    // Inicializa la cache de punteros a la memoria de vídeo.
    for (i = 0; i < NUM_LINES; i++) {
        line_pointers[i] = cpct_getScreenPtr(CPCT_VMEM_START, 0, i);
    }

    // Inicializa la tabla de estrellas.
    for (i = NUM_STARS, p = stars; i; i--, p++) {
        r = cpct_rand();
        p->x = r % NUM_COLS;
        p->y = r % NUM_LINES;
        p->s = r % 3 + 1; // tres velocidades: 1, 2 o 3
        switch (p->s) {
            // La velocidad determina el color: la idea es que la
            // velocidad está relacionada con la profundidad, cuanto
            // mas lenta mas lejana y mas tenue.
            //
            // Con el color se introduce una optimización (o se toma
            // un atajo, según se quiera ver): la coordenada x de la
            // estrella nos da el byte dentro de la línea y el color
            // nos da el pixel dentro del byte. Esto evita tener que
            // calcular que pixel es afectado y ajustar (desplazar) el
            // color, por contra no permite que dos estrellas
            // compartan el mismo byte (lo permite pero solo una es
            // visible) y hace que la distribución de las estrellas
            // sea "monótona" (las lentas el pixel 4, la intermedias
            // el 3 y las rápidas el 2). En la práctica no se percibe.
            //
            // Para mas detalles se puede consultar:
            // http://www.cpcmania.com/Docs/Programming/Pintando_pixeles_introduccion_a_la_memoria_de_video.htm

        case 1:
            p->c = 0x10; // 0001 0000: pixel 4, color 0b01 = 1
            break;

        case 2:
            p->c = 0x02; // 0000 0010: pixel 3, color 0b10 = 2
            break;

        case 3:
            p->c = 0x44; // 0100 0100: pixel 2, color 0b11 = 3
            break;
        }
    }
}

void field_do(void) {
    TStar *p = (TStar *)&stars;
    u8 *q;
    u8 count = NUM_STARS;
    u8 r;

    while (count--) {
        /* borra estrella */
        q = line_pointers[p->y] + p->x;
        *q = 0;
        /* mueve estrella */
        p->y += p->s;
        if (p->y >= NUM_LINES) {
            r = cpct_rand();
            p->x = (r & 63) + (r & 15); /* parecido a % 80, pero mas rápido */
            p->y = r & 7;               /* equivalente % 8, pero mas rápido */;
        }
        /* pinta estrella */
        q = line_pointers[p->y] + p->x;
        *q = p->c;
        p++;
    }
}

#ifdef DEBUG
u16 timer;

void interrupt_handler(void) {
    timer++;
}
#endif


void main(void) {
#ifdef DEBUG
    u16 time_last = 0;
    u8 fps = 0;
    char buffer[4] = "??";
#endif

    cpct_disableFirmware();
    cpct_setPalette(palette, 4);
    cpct_clearScreen(0);
    cpct_setBorder(HW_BLACK);
    cpct_srand8(0xFABADA);
    field_init();
#ifdef DEBUG
    timer = 0;
    cpct_setInterruptHandler(interrupt_handler);
#endif

    while (1) {
        cpct_waitVSYNC();
        /* cpct_setBorder(HW_RED); */
        field_do();
        /* cpct_setBorder(HW_GREEN); */
#ifdef DEBUG
        fps++;
        if (timer - time_last >= 300) {
            buffer[0] = hextab[fps >> 4];
            buffer[1] = hextab[fps & 15];
            time_last = timer;
            fps = 0;
        }
        cpct_drawStringM1_f(buffer, CPCT_VMEM_START, 1, 0);
#endif
    }
}
