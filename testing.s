section .data

    ; Размер матрицы n (1 байт, макс 255).
    n db 4

    ; Квадратная матрица 4x4 (64-битные элементы).
    ; Пример значений (можете изменить).
    matrix dq  9,  3,  1,  7
           dq 12,  4,  0,  2
           dq 11, 10,  6,  8
           dq 15, 14, 13,  5

    ; Переменная для выбора направления:
    ; +1 => сортировка по возрастанию
    ;  не 1 (например -1) => сортировка по убыванию
    sortDirection db 1

section .bss

    ; Буфер для временного хранения диагонали (макс 255 элементов по 8 байт).
    diag_buffer resb 2048

section .text
global _start

; ---------------------------------------------------------
; _start:
;  1) Считать n (размер матрицы).
;  2) Цикл по k = 0..(2n-2), где k = row + col для диагонали.
;  3) Для каждой диагонали собрать элементы в diag_buffer.
;  4) Сортировать вставками + бинарный поиск + проверка sortDirection.
;  5) Вернуть отсортированные элементы в matrix.
;  6) Выход (syscall exit).
; ---------------------------------------------------------

_start:
    ; Считать n (1 байт) в rax и расширить, затем r8 = n
    movzx rax, byte [n]
    mov   r8, rax

    ; k = 0..(2n-2)
    xor  rbx, rbx         ; k = 0

.diag_loop:
    ; Если k >= 2n - 1 => выходим.
    mov  rcx, r8
    shl  rcx, 1     ; rcx = 2*n
    sub  rcx, 1     ; rcx = 2n - 1
    cmp  rbx, rcx
    jge  .done_diags

    ; Определяем длину диагонали diag_length:
    ;  если k < n => diag_length = k + 1
    ;  иначе => diag_length = 2n-1 - k
    xor  rdi, rdi
    cmp  rbx, r8
    jl   .case_k_less

    ; k >= n
    mov  rdi, r8
    shl  rdi, 1
    sub  rdi, 1
    sub  rdi, rbx
    jmp  .diag_length_ready

.case_k_less:
    mov  rdi, rbx
    inc  rdi

.diag_length_ready:
    ; rdi = diag_length

    ; Сбор диагонали (row+col=k) в diag_buffer
    mov  rsi, diag_buffer  
    xor  rdx, rdx          ; счётчик в буфере
    xor  rax, rax          ; row = 0

.collect_loop:
    cmp  rax, r8
    jge  .collect_done

    ; col = k - row
    mov  rcx, rbx
    sub  rcx, rax

    ; Проверить 0 <= col < n
    cmp  rcx, r8
    jae  .skip_collect
    cmp  rcx, 0
    jl   .skip_collect

    ; Индекс = (n * row + col)*8
    mov  r9, r8
    imul r9, rax       
    add  r9, rcx      
    shl  r9, 3        
    mov  r10, matrix
    add  r10, r9
    mov  r11, [r10]   ; 64-битный элемент

    ; diag_buffer[rdx] = элемент
    mov  [rsi + rdx*8], r11
    inc  rdx

.skip_collect:
    inc  rax
    jmp  .collect_loop

.collect_done:
    ; rdi = diag_length
    ; если diag_length <= 1, сортировать не нужно
    cmp  rdi, 1
    jle  .no_sort_needed

    ; ------------------------------------------
    ; 4) Сортировка вставками + бинарный поиск
    ; ------------------------------------------

    xor  rax, rax
    mov  rax, 1        ; i = 1
.sort_outer:
    cmp  rax, rdi
    jge  .done_insertion

    ; current_value = diag_buffer[i]
    mov  rbx, [rsi + rax*8]

    ; ===== БИНАРНЫЙ ПОИСК c учетом sortDirection =====
    xor  rcx, rcx      ; left=0
    mov  r9, rax       ; right=i

.binsearch_loop:
    cmp  rcx, r9
    jge  .binsearch_end

    mov  r10, rcx
    add  r10, r9
    shr  r10, 1        ; mid=(left+right)/2

    mov  r11, [rsi + r10*8]  ; diag_buffer[mid]

    ; Считываем текущее направление sortDirection
    ; +1 => ascending, иначе => descending
    mov  al, [sortDirection]
    cmp  al, 1
    jne  .descending

    ; -- ВОЗРАСТАНИЕ: если diag_buffer[mid] <= current_value => идем вправо
    cmp  r11, rbx
    jle  .go_right
    mov  r9, r10
    jmp  .binsearch_loop

.descending:
    ; -- УБЫВАНИЕ: если diag_buffer[mid] >= current_value => идем вправо
    cmp  r11, rbx
    jge  .go_right
    mov  r9, r10
    jmp  .binsearch_loop

.go_right:
    inc  r10
    mov  rcx, r10
    jmp  .binsearch_loop

.binsearch_end:
    ; pos = rcx -> r10
    mov  r10, rcx

    ; ===== Сдвиг [pos..i-1] на 1 вправо =====
    mov  r8, rax
    dec  r8             ; j = i-1

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
    xor  rax, rax
    xor  rcx, rcx
.return_loop:
    cmp  rax, r8
    jge  .return_done

    ; col = k - row
    mov  r9, rbx
    sub  r9, rax
    cmp  r9, r8
    jae  .ret_skip
    cmp  r9, 0
    jl   .ret_skip

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
