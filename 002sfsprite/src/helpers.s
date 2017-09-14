;;;-----------------------------LICENSE NOTICE------------------------------------
;;;  This program is free software: you can redistribute it and/or modify
;;;  it under the terms of the GNU Lesser General Public License as published by
;;;  the Free Software Foundation, either version 3 of the License, or
;;;  (at your option) any later version.
;;;
;;;  This program is distributed in the hope that it will be useful,
;;;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;;  GNU Lesser General Public License for more details.
;;;
;;;  You should have received a copy of the GNU Lesser General Public License
;;;  along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;;------------------------------------------------------------------------------

    .module helpers

    .area _CODE

    .globl _stars
    .globl _line_pointers
    .globl cpct_getRandom_mxor_u8_asm

    NUM_STARS = 24
    NUM_LINES = 200

    .globl _ship
    .globl cpct_drawSolidBox_asm
    .globl cpct_getScreenPtr_asm

    CPCT_VMEM_START = 0xC000
    OF_X = 0
    OF_Y = 1
    OF_OX = 2
    OF_OY = 3
    SHIP_HEIGHT = 20
    SHIP_WIDTH = 6

    ;; -------------------------------------------------------------------------
    ;;
    ;; Versión en ensamblador de la función field_do:
    ;;
    ;;   void field_do(void) {
    ;;       TStar *p = (TStar *)&stars;
    ;;       u8 *q;
    ;;       u8 count = NUM_STARS;
    ;;       u8 r;
    ;;
    ;;       while (count--) {
    ;;           q = line_pointers[p->y] + p->x;
    ;;           if (*q == p->c) {
    ;;               // borra la estrella
    ;;               *q = 0;
    ;;           }
    ;;           // mueve la estrella
    ;;           p->y += p->s;
    ;;           if (p->y >= NUM_LINES) {
    ;;               r = cpct_rand();
    ;;               p->x = (r & 63) + (r & 15);
    ;;               p->y = r & 7;
    ;;           }
    ;;           q = line_pointers[p->y] + p->x;
    ;;           if (*q == 0) {
    ;;               // pinta la estrella si el fondo es negro.
    ;;               *q = p->c;
    ;;           }
    ;;           p++;
    ;;       }
    ;;   }

_field_do_asm::

    push af
    push bc
    push de
    push hl
    push ix

    ld ix, #_stars
    ld e, #NUM_STARS

fda_loop:
    ;; Calcula la dirección en la memoria de vídeo de la estrella.
    ;; Deja el resultado en HL.
    ld hl, #_line_pointers
    ld c, 1(ix)                 ; C = p->y
    xor a
    ld b, a                     ; BC = (u16)p->y
    add hl, bc
    add hl, bc                  ; HL = &line_pointers[p->y]
    ld c, (hl)
    inc hl
    ld b, (hl)                  ; BC = line_pointers[p->y]
    ld h, a                     ; A sigue valiendo 0
    ld l, 0(ix)                 ; HL = p->x
    add hl, bc                  ; HL = line_pointers[p->y] + p->x

    ;; Borra el pixel (byte) si el patrón en la memoria de vídeo
    ;; coincide con el de la estrella.
    ld a, (hl)                  ; A = *q
    sub 3(ix)                   ; *q == p->c
    jr nz, fda_no_erase
    ld (hl), a                  ; borra la estrella. En este punto A==0
fda_no_erase:

    ;; Desplaza la estrella verticalmente en funcion de su velocidad
    ;; (p->s). Si sale por debajo la reintroduce por arriba.
    ld a, 1(ix)                 ; A = p->y
    add 2(ix)                   ; A = p->y + p->s
    cp #NUM_LINES               ; (p->y + p->z) >= NUM_LINES
    jr c, fda_no_wrap
    ;; La estrella sale por la parte de abajo, se la reubica
    ;; aleatoriamente en una columna cualquiera y en una de las ocho
    ;; primeras filas.
    push de                     ; preserva E (el contador)
    call cpct_getRandom_mxor_u8_asm
                                ; L = u8 aleatorio
    pop de                      ; restaura E
    ld a, l
    and #63
    ld d, a
    ld a, l
    and #15
    add d
    ld 0(ix), a                 ; p->x = (r & 63) + (r & 15)
    ld a, l
    and #7                      ; A = r & 7
fda_no_wrap:
    ld 1(ix), a                 ; p->y = A

    ;; Calcula la dirección en la memoria de vídeo de la estrella.
    ;; Deja el resultado en HL.
    ld hl, #_line_pointers
    ld c, a                     ; Aprovechamos que tras actualizar
                                ; p->y su nuevo valor está en A
    xor a
    ld b, a                     ; BC = (u16)p->y.
    add hl, bc
    add hl, bc                  ; HL = &line_pointers[p->y]
    ld c, (hl)
    inc hl
    ld b, (hl)                  ; BC = line_pointers[p->y]
    ld h, a                     ; A sigue valiendo 0
    ld l, 0(ix)                 ; HL = (u16)p->x
    add hl, bc                  ; HL = line_pointers[p->y] + p->x

    ;; pinta el pixel, si está en negro
    ld a, (hl)                  ; A = píxel memoria de vídeo
    or a, a
    jr nz, fda_no_paint         ; está en negro?
    ld a, 3(ix)                 ; A = p->c
    ld (hl), a                  ; pintar
fda_no_paint:

    ld bc, #4
    add ix, bc                  ; p++
    dec e                       ; count--
    jr nz, fda_loop

    pop ix
    pop hl
    pop de
    pop bc
    pop af

    ret


    ;; -------------------------------------------------------------------------
    ;;
    ;; Versión en ensamblador de la función ship_erase:
    ;;
    ;; void ship_erase(void) {
    ;;     u8 *p = NULL;
    ;;
    ;;     if (ship.oy < ship.y) {
    ;;         p = cpct_getScreenPtr(CPCT_VMEM_START, ship.ox, ship.oy);
    ;;         cpct_drawSolidBox(p, 0, SHIP_WIDTH, ship.y - ship.oy);
    ;;     } else if (ship.oy > ship.y) {
    ;;         p = cpct_getScreenPtr(CPCT_VMEM_START, ship.ox, ship.y + SHIP_HEIGHT);
    ;;         cpct_drawSolidBox(p, 0, SHIP_WIDTH, ship.oy - ship.y);
    ;;     }
    ;;
    ;;     if (ship.ox < ship.x) {
    ;;         p = cpct_getScreenPtr(CPCT_VMEM_START, ship.ox, max(ship.y, ship.oy));
    ;;         cpct_drawSolidBox(p, 0, ship.x - ship.ox,
    ;;                           SHIP_HEIGHT - abs(ship.y - ship.oy))
    ;;     } else if (ship.ox > ship.x) {
    ;;         p = cpct_getScreenPtr(CPCT_VMEM_START, ship.x + SHIP_WIDTH,
    ;;                               max(ship.y, ship.oy));
    ;;         cpct_drawSolidBox(p, 0, ship.ox - ship.x,
    ;;                           SHIP_HEIGHT - abs(ship.y - ship.oy));
    ;;     }
    ;; }
    ;;
    ;; Esta función borra solamente el área expuesta tras el
    ;; desplazamiento del sprite. En total hay 8 casos, dependiendo de
    ;; si el desplazamiento es horizontal, vertical o una combinación
    ;; de ambos y si es positivo o negativo. En la práctica es
    ;; suficiente con descomponer el desplazamiento en las componentes
    ;; vertical y horizontal. Al procesar cada componente se borra una
    ;; región del área expuesta.
    ;;
    ;; (ox, oy)
    ;;    +--------------------+              +--------------------+
    ;;    |   (x, y)           |              |                    |
    ;;    |     +--------------------+        +-----+--------------+
    ;;    |     |                    |        |     |
    ;;    |     |                    |        |     |
    ;;    |     |                    |        |     |
    ;;    +-----|                    |        +-----+
    ;;          |                    |
    ;;          +--------------------+
    ;;

_ship_erase_asm::

    push af
    push bc
    push de
    push hl
    push ix

    ld ix, #_ship

    ;; Procesar la componente vertical

    ld a, OF_OY(ix)             ; A = ship.oy
    cp OF_Y(ix)                 ; comparar con ship.y
    jr z, sher_end_vert         ; ship.oy == ship.y: no hay
                                ; desplazamiento vertical
    jr c, sher_down             ; ship.oy < ship.y: abajo

sher_up:
    ;; el sprite se ha desplazado hacia arriba (ship.oy > ship.y)

    ;; p = cpct_getScreenPtr(CPCT_VMEM_START, ship.ox, ship.y + SHIP_HEIGHT);
    ld de, #CPCT_VMEM_START
    ld c, OF_OX(ix)             ; C = ship.ox
    ld a, OF_Y(ix)              ; A = ship.y
    add #SHIP_HEIGHT
    ld b, a                     ; B = ship.y + SHIP_HEIGHT
    call cpct_getScreenPtr_asm

    ;; cpct_drawSolidBox(p, 0, SHIP_WIDTH, ship.oy - ship.y);
    ld d, h
    ld e, l                     ; DE = HL = screen ptr
    ld c, #SHIP_WIDTH           ; C = width
    ld a, OF_OY(ix)             ; A = ship.oy
    sub OF_Y(ix)                ; A = ship.oy - ship.y
    ld b, a                     ; B = ship.oy - ship.y = height
    xor a                       ; A = 0
    call cpct_drawSolidBox_asm
    jr sher_end_vert

sher_down:
    ;; el sprite se ha desplazado hacia abajo (ship.oy < ship.y)

    ;; p = cpct_getScreenPtr(CPCT_VMEM_START, ship.ox, ship.oy);
    ld de, #CPCT_VMEM_START
    ld c, OF_OX(ix)             ; C = ship.ox
    ld b, OF_OY(ix)             ; B = ship.oy
    call cpct_getScreenPtr_asm

    ;; cpct_drawSolidBox(p, 0, SHIP_WIDTH, ship.y - ship.oy);
    ld d, h
    ld e, l                     ; DE = HL = screen ptr
    ld c, #SHIP_WIDTH           ; C = width
    ld a, OF_Y(ix)              ; A = ship.y
    sub OF_OY(ix)               ; A = ship.y - ship.oy
    ld b, a                     ; B = ship.y - ship.oy = height
    xor a                       ; A = 0
    call cpct_drawSolidBox_asm

sher_end_vert:

    ;; Procesar la componente horizontal.

    ld a, OF_OX(ix)             ; A = ship.ox
    ld b, OF_X(ix)              ; B = ship.x
    cp b
    jr z, sher_end_hor          ; ship.ox == ship.x; no hay
                                ; desplazamiento horizontal
    jr c, sher_right            ; ship.ox < ship.x: derecha

sher_left:
    ;; el sprite se ha desplazado hacia la izquierda (ship.ox > ship.x)

    ;; p = cpct_getScreenPtr(CPCT_VMEM_START, ship.x + SHIP_WIDTH, max(ship.y, ship.oy));
    ld de, #CPCT_VMEM_START
    ld a, OF_X(ix)              ; A = ship.x
    add #SHIP_WIDTH             ; A = ship.x + SHIP_WIDTH
    ld c, a                     ; C = ship.x + SHIP_WIDTH
    ;; calcula el máximo entre ship.y y ship.oy dejando el resultado
    ;; en B
    ld a, OF_Y(ix)              ; A = ship.y
    ld b, OF_OY(ix)             ; B = ship.oy
    cp b
    jr c, sher_max_1            ; jump si ship.y < ship.oy, en cuyo
                                ; caso en B ya tenemos el máximo
    ld b, a                     ; en este punto ship.y >= ship.oy, el
                                ; máximo está en A, lo cargamos en B.
sher_max_1:
    call cpct_getScreenPtr_asm

    ;; cpct_drawSolidBox(p, 0, ship.ox - ship.x, SHIP_HEIGHT - abs(ship.y - ship.oy));
    ld d, h
    ld e, l                     ; DE = HL = screen ptr
    ld a, OF_OX(ix)             ; A = ship.ox
    sub OF_X(ix)                ; A = ship.ox - ship.x
    ld c, a                     ; C = ship.ox - ship.x = width

    ld a, OF_Y(ix)              ; A = ship.y
    sub OF_OY(ix)               ; A = ship.y - ship.oy
    or a                        ; actualizar flags
    jp p, sher_abs_1            ; salta si positivo
    neg                         ; cambia el signo
sher_abs_1:
    ld b, a                     ; B = abs(ship.y - ship.oy)
    ld a, #SHIP_HEIGHT
    sub b                       ; A = SHIP_HEIGHT - abs(ship.y - ship.oy)
    ld b, a                     ; B = SHIP_HEIGHT - abs(ship.y - ship.oy)
    xor a                       ; A = 0
    call cpct_drawSolidBox_asm
    jr sher_end_hor

sher_right:
    ;; el sprite se ha desplazado hacia la derecha (ship.ox < ship.x)

    ;; p = cpct_getScreenPtr(CPCT_VMEM_START, ship.ox, max(ship.y, ship.oy))
    ld de, #CPCT_VMEM_START
    ld c, OF_OX(ix)             ; C = ship.ox
    ;; calcula el máximo entre ship.y y ship.oy dejando el resultado
    ;; en B
    ld a, OF_Y(ix)              ; A = ship.y
    ld b, OF_OY(ix)             ; B = ship.oy
    cp b
    jr c, sher_max_2            ; jump si ship.y < ship.oy, en cuyo
                                ; caso en B ya tenemos el máximo
    ld b, a                     ; en este punto ship.y >= ship.oy, el
                                ; máximo está en A, lo cargamos en B.
sher_max_2:
    call cpct_getScreenPtr_asm

    ;; cpct_drawSolidBox(p, 0, ship.x - ship.ox, SHIP_HEIGHT - abs(ship.y - ship.oy));
    ld d, h
    ld e, l                     ; DE = HL = screen ptr
    ld a, OF_X(ix)              ; A = ship.x
    sub OF_OX(ix)               ; A = ship.x - ship.ox
    ld c, a                     ; C = width

    ld a, OF_Y(ix)              ; A = ship.y
    sub OF_OY(ix)               ; A = ship.y - ship.oy
    or a                        ; ajustar flags
    jp p, sher_abs_2            ; salta si positivo
    neg                         ; cambia el signo
sher_abs_2:
    ld b, a                     ; B = abs(ship.y - ship.oy)
    ld a, #SHIP_HEIGHT
    sub b                       ; A = SHIP_HEIGHT - abs(ship.y - ship.oy)
    ld b, a                     ; B = SHIP_HEIGHT - abs(ship.y - ship.oy)
    xor a                       ; A = 0
    call cpct_drawSolidBox_asm

sher_end_hor:

    pop ix
    pop hl
    pop de
    pop bc
    pop af

    ret

    .area _DATA
