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

#define SCREEN_WIDTH NUM_COLS
#define SCREEN_HEIGHT NUM_LINES

// definiendo DEBUG se muestra el número de FPS
#undef DEBUG

/* Colores de la paleta:
 * fondo, estrella lenta, intermedia i rápida
 */
#define NUM_COLORS 9
const u8 palette[] = {
    HW_BLACK,
    HW_YELLOW, HW_PASTEL_YELLOW, HW_BRIGHT_WHITE,
    HW_WHITE, HW_MAUVE, HW_PASTEL_CYAN, HW_BRIGHT_RED, HW_BRIGHT_GREEN
};
const char hextab[] = "0123456789ABCDEF";

/* line_pointers almacena la dirección de inicio de cada línea de la
 * memoria de vídeo. Evita utilizar cpct_getScreenPtr (costosa en
 * CPU).
 */
u8 *line_pointers[NUM_LINES];

#ifdef DEBUG
u16 timer;

void interrupt_handler(void) {
    timer++;
}

void display_u8_hex(u8 v, u8 *p) {
    static char buffer[3];

    buffer[0] = hextab[v >> 4];
    buffer[1] = hextab[v & 15];
    buffer[2] = 0;
    cpct_drawStringM0(buffer, p, 4, 0);
}

#define display_fps(fps) display_u8_hex(fps, CPCT_VMEM_START)

#define display_ship_coords() {                         \
        display_u8_hex(ship.x, CPCT_VMEM_START + 10);   \
        display_u8_hex(ship.y, CPCT_VMEM_START + 18);   \
    }

#define display_ship_old_coords() {                     \
        display_u8_hex(ship.ox, CPCT_VMEM_START + 28);  \
        display_u8_hex(ship.oy, CPCT_VMEM_START + 36);  \
    }

#endif


/*              _ _           */
/*  ____ __ _ _(_) |_ ___ ___ */
/* (_-< '_ \ '_| |  _/ -_|_-< */
/* /__/ .__/_| |_|\__\___/__/ */
/*    |_|                     */

// ancho de la nave, en bytes
#define SHIP_WIDTH 6
#define SHIP_HEIGHT 20

const unsigned char sprite_nave[SHIP_WIDTH * SHIP_HEIGHT] = {
	0x00, 0x00, 0x14, 0x28, 0x00, 0x00,
	0x00, 0x00, 0x78, 0x34, 0x00, 0x00,
	0x00, 0x14, 0xF0, 0xF0, 0x28, 0x00,
	0x00, 0x14, 0xF0, 0xF0, 0x88, 0x00,
	0x00, 0x14, 0xF0, 0xF0, 0x88, 0x00,
	0x00, 0x14, 0xB0, 0x70, 0x88, 0x00,
	0x00, 0x14, 0x64, 0x98, 0x88, 0x00,
	0x00, 0x00, 0xCC, 0xCC, 0x00, 0x00,
	0x00, 0x00, 0x34, 0x38, 0x00, 0x00,
	0x80, 0x00, 0x98, 0x64, 0x00, 0x40,
	0x80, 0x00, 0x44, 0x88, 0x00, 0x40,
	0x20, 0x00, 0x44, 0x88, 0x00, 0x10,
	0x88, 0x00, 0xEC, 0x89, 0x00, 0x44,
	0x88, 0x14, 0x64, 0x98, 0x28, 0x44,
	0x88, 0x3C, 0x6C, 0x9C, 0x3C, 0x44,
	0x88, 0x6C, 0x6C, 0x9C, 0x9C, 0x44,
	0x9C, 0xCC, 0xCC, 0xCC, 0xCC, 0x6C,
	0xCC, 0xCC, 0x64, 0x98, 0xCC, 0xCC,
	0xCC, 0xCC, 0x64, 0x98, 0xCC, 0xCC,
	0x44, 0xCC, 0x64, 0x98, 0xCC, 0x88
};


/*     _    _       */
/*  __| |_ (_)_ __  */
/* (_-< ' \| | '_ \ */
/* /__/_||_|_| .__/ */
/*           |_|    */

typedef struct {
    u8 x;  // cordenada X, por el momento en bytes
    u8 y;  // cordenada Y
    u8 ox; // coordenada X anterior, se utiliza para borrar
    u8 oy; // ídem.
    i8 dx; // velocidad X, en bytes/tiempo
    i8 dy; // velocidad Y
    i8 dirty;
} TShip;

TShip ship;

void ship_init(void) {
    ship.x = (SCREEN_WIDTH - SHIP_WIDTH) / 2;
    ship.y = SCREEN_HEIGHT - SHIP_HEIGHT - 1;
    ship.ox = ship.x;
    ship.oy = ship.y;
    ship.dx = 0;
    ship.dy = 0;
    ship.dirty = 0;
}

void ship_update(void) {
    if (ship.dx) {
        ship.dirty = 1;
        ship.x += ship.dx;
        if (ship.x > 200) {
            // Comprueba si es negativo. Me curo en salud usando un valor
            // ligeramente mas grande que el ancho de la pantalla (medido en
            // pixels, por si mas adelante me animo a implementar
            // desplazamiento pixel a pixel en lugar de byte a byte).
            ship.x = 0;
        } else if (ship.x > (SCREEN_WIDTH - SHIP_WIDTH)) {
            ship.x = SCREEN_WIDTH - SHIP_WIDTH;
        }
    }
    if (ship.dy) {
        ship.dirty = 1;
        ship.y += ship.dy;
        if (ship.y > 240) {
            // Comprueba si es negativo. Me curo en salud usando un valor
            // ligeramente mas grande que el alto de la pantalla.
            ship.y = 0;
        } else if (ship.y > (SCREEN_HEIGHT - SHIP_HEIGHT)) {
            ship.y = SCREEN_HEIGHT - SHIP_HEIGHT;
        }
    }
}

void ship_erase(void) {
    u8 *p = cpct_getScreenPtr(CPCT_VMEM_START, ship.ox, ship.oy);

    cpct_drawSolidBox(p, 0, SHIP_WIDTH, SHIP_HEIGHT);
}

void ship_draw(void) {
    u8 *p = cpct_getScreenPtr(CPCT_VMEM_START, ship.x, ship.y);

    cpct_drawSprite(sprite_nave, p, SHIP_WIDTH, SHIP_HEIGHT);
    ship.ox = ship.x;
    ship.oy = ship.y;
    ship.dirty = 0;
}


/*     _             __ _     _    _  */
/*  __| |_ __ _ _ _ / _(_)___| |__| | */
/* (_-<  _/ _` | '_|  _| / -_) / _` | */
/* /__/\__\__,_|_| |_| |_\___|_\__,_| */

typedef struct {
    u8 x; /* coordenada x, en bytes */
    u8 y; /* coordenada y, en bytes */
    u8 s; /* velocidad              */
    u8 c; /* color                  */
} TStar;

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
            // sea "monótona" (las lentas el pixel 2, la intermedias
            // el 1 y las rápidas el 2). Se podria añadir una
            // componente aleatoria para escoger un pixel u otro, pero
            // en la práctica no se percibe.
            //
            // Para mas detalles se puede consultar:
            // http://www.cpcmania.com/Docs/Programming/Pintando_pixeles_introduccion_a_la_memoria_de_video.htm

        case 1:
            p->c = 0x40; // 0100 0000: pixel 1, pen 0b0000 = 0; pixel 2, pen 0b0001 = 1
            break;

        case 2:
            p->c = 0x08; // 0000 1000: pixel 1, pen 0b0010 = 2; pixel 2, pen 0b0000 = 0
            break;

        case 3:
            p->c = 0x44; // 0100 0100: pixel 1, pen 0b0000 = 0; pixel 2, pen 0b0011 = 3
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
        q = line_pointers[p->y] + p->x;
        if (*q == p->c) {
            // borra la estrella si su patrón de color coincide con el de la
            // pantalla. No es 100% fiable, si se deja la nave quieta un rato
            // las estrellas rápidas (0x44) i las lentas (0x40) pueden borrar
            // pixels de la nave con el mismo patrón. El patrón 0x08 no se
            // utiliza en el sprite de la nave con lo que no hay problema con
            // las intermedias.
            *q = 0;
        }
        // mueve la estrella
        p->y += p->s;
        if (p->y >= NUM_LINES) {
            r = cpct_rand();
            p->x = (r & 63) + (r & 15); /* parecido a % 80, pero mas rápido */
            p->y = r & 7;               /* equivalente % 8, pero mas rápido */;
        }
        q = line_pointers[p->y] + p->x;
        if (*q == 0) {
            // pinta la estrella si el fondo es negro.
            *q = p->c;
        }
        p++;
    }
}


/*  _          _         _      */
/* | |_ ___ __| |__ _ __| |___  */
/* |  _/ -_) _| / _` / _` / _ \ */
/*  \__\___\__|_\__,_\__,_\___/ */

void kbd_read(void) {
    cpct_scanKeyboard();
    ship.dx = 0;
    ship.dy = 0;

    if (cpct_isAnyKeyPressed()) {
        if (cpct_isKeyPressed(Key_J)) {
            ship.dx = -1;
        }
        if (cpct_isKeyPressed(Key_L)) {
            ship.dx = 1;
        }
        if (cpct_isKeyPressed(Key_I)) {
            ship.dy = -2;
        }
        if (cpct_isKeyPressed(Key_K)) {
            ship.dy = 2;
        }
    }
}


/*             _       */
/*  _ __  __ _(_)_ _   */
/* | '  \/ _` | | ' \  */
/* |_|_|_\__,_|_|_||_| */

void main(void) {
#ifdef DEBUG
    u16 time_last = 0;
    u8 fps = 0;
    char buffer[4] = "??";
#endif

    cpct_disableFirmware();
    cpct_setVideoMode(0);
    cpct_setPalette(palette, NUM_COLORS);
    cpct_clearScreen(0);
    cpct_setBorder(HW_BLACK);
    cpct_srand8(0xFABADA);
    field_init();
    ship_init();

    ship_draw();

#ifdef DEBUG
    timer = 0;
    cpct_setInterruptHandler(interrupt_handler);
    display_fps(fps);
#endif

    while (1) {
        kbd_read();
        ship_update();
#ifdef DEBUG
        display_ship_coords();
        display_ship_old_coords();
#endif
        cpct_waitVSYNC();
        /* cpct_setBorder(HW_RED); */
        if (ship.dirty) {
            ship_erase();
            ship_draw();
        }
        field_do();
        /* cpct_setBorder(HW_GREEN); */

#ifdef DEBUG
        fps++;
        if (timer - time_last >= 300) {
            display_fps(fps);
            time_last = timer;
            fps = 0;
        }
#endif

    }
}
