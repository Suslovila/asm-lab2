section .data

    ; Размер матрицы (1 байт, до 255).
    n db 4

    ; Квадратная матрица 4x4, 64-битные элементы (dq).
    ; Пример:
    matrix dq  9,  3,  1,  7
           dq 12,  4,  0,  2
           dq 11, 10,  6,  8
           dq 15, 14, 13,  5

    ; Выбор направления сортировки:
    ;   1 => по возрастанию
    ;  -1 => по убыванию (или любое != 1)
    sortDirection db 1

section .bss

    ; Буфер для одной диагонали (до 255 элементов * 8 байт).
    diag_buffer resb 2048

section .text
global _start

; ---------------------------------------------------------
; _start — точка входа
;  1) Считать n в r8
;  2) k => r13, идти 0..(2n-2)
;  3) Для каждого k собрать diag => diag_buffer
;  4) Сортировка (Insertion+BinarySearch) + sortDirection
;  5) Вернуть отсортированное в matrix
;  6) exit(0)
; ---------------------------------------------------------
_start:
    ; 1) Считать n (1 байт), расширить до 64 бит => r8
    movzx rax, byte [n]
    mov   r8, rax         ; r8 = n (64-битный)

    ; Вычислим (2n - 1) заранее и сохраним в r12 (чтобы не пересчитывать в каждой итерации)
    mov   r12, r8
    shl   r12, 1          ; r12 = 2n
    sub   r12, 1          ; r12 = 2n - 1

    ; k = 0..(2n-2), храним в r13
    xor   r13, r13        ; k = 0

.diag_loop:
    ; если k >= (2n - 1), выходим
    cmp   r13, r12
    jge   .done_diags

    ; -----------------------------------------------------
    ; Определить длину диагонали (diag_len) => rdi
    ;   если k < n => diag_len = k + 1
    ;   иначе      => diag_len = (2n - 1) - k
    ; -----------------------------------------------------
    xor   rdi, rdi
    cmp   r13, r8
    jl    .case_k_less

    ; k >= n
    mov   rdi, r12        ; rdi = 2n - 1
    sub   rdi, r13        ; rdi = 2n - 1 - k
    jmp   .diag_len_ready

.case_k_less:
    mov   rdi, r13        ; rdi = k
    inc   rdi             ; rdi = k + 1

.diag_len_ready:
    ; rdi = diag_len

    ; -----------------------------------------------------
    ; Собрать diag => diag_buffer
    ; row => rax, col => (k - row), индекс diag => rdx
    ; -----------------------------------------------------
    mov   rsi, diag_buffer
    xor   rdx, rdx        ; rdx=0 (индекс в diag_buffer)
    xor   rax, rax        ; rax=0 (row=0)

.collect_loop:
    cmp   rax, r8
    jge   .collect_done

    ; col = k - row
    mov   rcx, r13
    sub   rcx, rax

    ; Проверка col в [0..n)
    cmp   rcx, r8
    jae   .skip_collect
    cmp   rcx, 0
    jl    .skip_collect

    ; index = (row*n + col)*8
    mov   r9, r8
    imul  r9, rax      ; row * n
    add   r9, rcx      ; (row*n + col)
    shl   r9, 3        ; *8
    mov   r10, matrix
    add   r10, r9
    mov   r11, [r10]   ; 64-битный элемент matrix[row,col]

    ; diag_buffer[rdx] = r11
    mov   [rsi + rdx*8], r11
    inc   rdx

.skip_collect:
    inc   rax
    jmp   .collect_loop

.collect_done:
    ; rdi = diag_len
    cmp   rdi, 1
    jle   .no_sort_needed

    ; -----------------------------------------------------
    ; 4) Сортировка вставками + бинарный поиск
    ;    diag_buffer[0..diag_len-1]
    ; -----------------------------------------------------
    xor   rax, rax
    mov   rax, 1       ; i=1

.sort_outer:
    cmp   rax, rdi
    jge   .done_insertion

    ; current_value = diag_buffer[i], хранится в rbx
    mov   rbx, [rsi + rax*8]

    ; БИНАРНЫЙ ПОИСК (left=0, right=i)
    xor   rcx, rcx     ; left=0
    mov   r9, rax      ; right=i

.binsearch_loop:
    cmp   rcx, r9
    jge   .binsearch_end

    mov   r10, rcx
    add   r10, r9
    shr   r10, 1       ; mid = (left+right)/2
    mov   r11, [rsi + r10*8]

    ; Смотрим sortDirection (+1 => ascending, иначе => descending)
    mov   al, [sortDirection]
    cmp   al, 1
    jne   .descending

    ; -------- Возрастание --------
    cmp   r11, rbx
    jle   .go_right       ; если diag_buffer[mid] <= currVal => идём вправо
    mov   r9, r10         ; right=mid
    jmp   .binsearch_loop

.descending:
    ; -------- Убывание --------
    cmp   r11, rbx
    jge   .go_right       ; если diag_buffer[mid] >= currVal => идём вправо
    mov   r9, r10
    jmp   .binsearch_loop

.go_right:
    inc   r10
    mov   rcx, r10        ; left = mid+1
    jmp   .binsearch_loop

.binsearch_end:
    ; pos => r10
    mov   r10, rcx

    ; Сдвиг [pos..(i-1)] → [pos+1.. i]
    ; j = i-1 => используем r14, чтобы НЕ затирать r8= n
    mov   r14, rax
    dec   r14         ; j = i-1

.shift_loop:
    cmp   r14, r10
    jl    .insert_value

    mov   r11, [rsi + r14*8]
    mov   [rsi + (r14+1)*8], r11
    dec   r14
    jmp   .shift_loop

.insert_value:
    mov   [rsi + r10*8], rbx

    inc   rax
    jmp   .sort_outer

.done_insertion:
.no_sort_needed:

    ; -----------------------------------------------------
    ; 5) Возвращаем отсортированную диагональ в matrix
    ; -----------------------------------------------------
    xor   rax, rax    ; row=0
    xor   rcx, rcx    ; индекс diag_buffer=0

.return_loop:
    cmp   rax, r8
    jge   .return_done

    ; col = k - row  (k => r13)
    mov   r9, r13
    sub   r9, rax
    cmp   r9, r8
    jae   .ret_skip
    cmp   r9, 0
    jl    .ret_skip

    ; matrix[row,col] = diag_buffer[rcx]
    mov   r10, r8
    imul  r10, rax
    add   r10, r9
    shl   r10, 3
    mov   r11, matrix
    add   r11, r10

    mov   r14, [rsi + rcx*8]
    mov   [r11], r14
    inc   rcx

.ret_skip:
    inc   rax
    jmp   .return_loop

.return_done:

    ; k++
    inc   r13
    jmp   .diag_loop

.done_diags:

    ; 6) exit(0)
    mov   rax, 60
    xor   rdi, rdi
    syscall
