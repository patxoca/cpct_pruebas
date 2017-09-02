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

    .area _CODE

    .globl _stars
    .globl _line_pointers
    .globl cpct_getRandom_mxor_u8

    NUM_STARS = 24
    NUM_LINES = 200

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
    cp 3(ix)                    ; *q == p->c
    jr nz, fda_no_erase
    xor a
    ld (hl), a                  ; borra la estrella
fda_no_erase:

    ;; Desplaza la estrella verticalmente en funcion de su velocidad
    ;; (p->s). Si sale por debajo la reintroduce por arriba.
    ld a, 1(ix)                 ; A = p->y
    add 2(ix)                   ; A = p->y + p->s
    cp #NUM_LINES               ; (p->y + p->z) >= NUM_LINES
    jr c, fda_no_wrap
    jr z, fda_no_wrap
    ;; La estrella sale por la parte de abajo, se la reubica
    ;; aleatoriamente en una columna cualquiera y en una de las ocho
    ;; primeras filas.
    push de                     ; preserva E (el contador)
    call cpct_getRandom_mxor_u8 ; L = u8 aleatorio
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
                                ; p->y su nuevo valor está A
    xor a
    ld b, a                     ; BC = p->y.
    add hl, bc
    add hl, bc                  ; HL = &line_pointers[p->y]
    ld c, (hl)
    inc hl
    ld b, (hl)                  ; BC = line_pointers[p->y]
    ld h, a                     ; A sigue valiendo 0
    ld l, 0(ix)                 ; HL = p->x
    add hl, bc                  ; HL = line_pointers[p->y] + p->x

    ;; pinta el pixel, si está en negro
    ld a, (hl)                  ; A = píxel memoria de vídeo
    or a, a
    jr nz, fda_no_paint         ; está en negro?
    ld a, 3(ix)                 ; A = p->c
    ld (hl), a                  ; pintar
fda_no_paint:

    inc ix                      ; p++
    inc ix
    inc ix
    inc ix
    dec e                       ; count--
    jr nz, fda_loop

    pop ix
    pop hl
    pop de
    pop bc
    pop af

    ret

    .area _DATA
