; =========================================================
; lab_insertion_no_functions.asm
; Сортировка каждой диагонали (параллельной побочной)
; 64-битная матрица, алгоритм: insertion sort + binary search
; Всё в одном месте (без вызовов подпрограмм).
; =========================================================

section .data

    ; Размер матрицы n (1 байт, макс 255).
    n db 4

    ; Квадратная матрица 4x4 (64-битные элементы).
    ; Пример значений (можете изменить).
    matrix dq  9,  3,  1,  7
           dq 12,  4,  0,  2
           dq 11, 10,  6,  8
           dq 15, 14, 13,  5

section .bss

    ; Буфер для временного хранения диагонали (макс 255 элементов по 8 байт).
    diag_buffer resb 2048

section .text
global _start

; ---------------------------------------------------------
; _start:
; 1) Считать n (размер).
; 2) Цикл по k = 0..(2n-2).
; 3) Для каждой диагонали собрать элементы -> diag_buffer
; 4) Сортировка вставками + бинарный поиск (встроенно).
; 5) Вернуть отсортированные элементы обратно в matrix.
; 6) exit(0).
; ---------------------------------------------------------
_start:
    ; 1) Считать n (1 байт).
    movzx rax, byte [n]   ; rax = n (8 бит -> 64 бит)
    mov   r8, rax         ; r8 = n (сохраняем размер матрицы в r8)

    ; k = 0..(2n-2)
    xor  rbx, rbx         ; зануляем,k = 0

; выбираем следующую диагональ и идем от 0 до 2k - 1
.diag_loop:
    ; Если k >= 2n - 1 -> выходим.
    mov  rcx, r8
    shl  rcx, 1           ; rcx = 2 * n
    sub  rcx, 1           ; rcx = 2n - 1
    cmp  rbx, rcx
    jge  .done_diags

    ; 2) Определяем длину диагонали diag_len:
    ;    если k < n, diag_len = k+1
    ;    иначе diag_len = 2n-1 - k
    xor  rdi, rdi
    cmp  rbx, r8
    ;если k < n
    jl   .case_k_less
    ; k >= n
    mov  rdi, r8
    shl  rdi, 1
    sub  rdi, 1
    sub  rdi, rbx
    jmp  .diag_len_ready
.case_k_less:
    mov  rdi, rbx
    inc  rdi


; переносим диагональ в буфер
.diag_len_ready:
    ; имеем: rdi = diag_len

    ; 3) Собираем диагональ [row+col = k] в diag_buffer
    
    mov  rsi, diag_buffer  ; указатель на diag_buffer
    xor  rdx, rdx          ; счётчик записанных элементов = 0
    xor  rax, rax          ; row = 0

.collect_loop:
    cmp  rax, r8
    jge  .collect_done

    ; col = k - row
    mov  rcx, rbx
    sub  rcx, rax

    ; Проверим, что 0 <= col < n
    cmp  rcx, r8
    jae  .skip_collect
    cmp  rcx, 0
    jl   .skip_collect

    ; Индекс = row*n + col, каждый элемент = 8 байт (dq)
    mov  r9, r8
    imul r9, rax          ; r9 = row * n
    add  r9, rcx          ; r9 = row*n + col
    shl  r9, 3            ; r9 *= 8
    mov  r10, matrix
    add  r10, r9          ; адрес matrix[row,col]
    mov  r11, [r10]       ; берём 64-битный элемент

    ; diag_buffer[rdx] = элемент
    mov  [rsi + rdx*8], r11
    inc  rdx

.skip_collect:
    inc  rax  ; row++
    jmp  .collect_loop


.collect_done:
    ; rdi = diag_len

    ; если длина диагонали 1 - выходим
    cmp  rdi, 1
    jle  .no_sort_needed

    ; 4) Сортировка вставками + бинарный поиск (встроенно).
    ; Внешний цикл i = 1..(diag_len-1)

    ;подготовка
    xor  rax, rax
    mov  rax, 1           ; i = 1

    ;rax - индекс
    ; rdi - длина диагонали
.sort_outer:
    cmp  rax, rdi
    jge  .done_insertion

    ; current_value = diag_buffer[i]
    mov  rbx, [rsi + rax*8]

    ; ===== БИНАРНЫЙ ПОИСК =====
    xor  rcx, rcx         ; left = 0
    mov  r9, rax          ; right = i
.binsearch_loop:
    cmp  rcx, r9
    jge  .binsearch_end
    mov  r10, rcx
    add  r10, r9
    shr  r10, 1           ; mid = (left+right)/2
    mov  r11, [rsi + r10*8]  ; diag_buffer[mid]
    cmp  r11, rbx
    jle  .go_right
    mov  r9, r10
    jmp  .binsearch_loop
.go_right:
    inc  r10
    mov  rcx, r10
    jmp  .binsearch_loop
.binsearch_end:
    ; pos = rcx
    mov  r10, rcx

    ; ===== Сдвиг элементов [pos..i-1] на 1 вправо =====
    mov  r8, rax
    dec  r8              ; j = i-1
.shift_loop:
    cmp  r8, r10
    jl   .insert_value
    mov  r11, [rsi + r8*8]
    mov  [rsi + (r8+1)*8], r11
    dec  r8
    jmp  .shift_loop

.insert_value:
    mov  [rsi + r10*8], rbx

    inc  rax
    jmp  .sort_outer

.done_insertion:

.no_sort_needed:

    ; 5) Возвращаем отсортированную диагональ в matrix
    xor  rax, rax   ; row=0
    xor  rcx, rcx   ; индекс diag_buffer=0
.return_loop:
    cmp  rax, r8
    jge  .return_done

    ; col = k - row
    mov  r9, rbx
    sub  r9, rax
    ; Проверка col в [0..n-1]
    cmp  r9, r8
    jae  .ret_skip
    cmp  r9, 0
    jl   .ret_skip

    ; matrix[row,col] = diag_buffer[rcx]
    mov  r10, r8
    imul r10, rax
    add  r10, r9
    shl  r10, 3
    mov  r11, matrix
    add  r11, r10
    mov  r12, [rsi + rcx*8]
    mov  [r11], r12

    inc  rcx

.ret_skip:
    inc  rax
    jmp  .return_loop
.return_done:

    ; k++
    inc  rbx
    jmp  .diag_loop

.done_diags:

    ; 6) syscall exit(0)
    mov  rax, 60
    xor  rdi, rdi
    syscall
