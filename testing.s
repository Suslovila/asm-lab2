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
;  1) Считать n (1 байт) в r8 (никогда не трогаем r8 дальше).
;  2) k => r13, k=0..(2n-2)
;  3) diag => diag_buffer
;  4) Insertion Sort + Binary Search (с учётом sortDirection).
;  5) Возврат отсортированных данных.
;  6) syscall exit(0).
; ---------------------------------------------------------
_start:
    ; 1) Считать n (1 байт), в r8 (64-бит)
    movzx rax, byte [n]
    mov   r8, rax         ; r8 = n

    ; Вместо "2n - 1" вычислим "2n - 2", чтобы обрабатывать k до (2n-2) включительно
    mov   r12, r8
    shl   r12, 1          ; r12 = 2*n
    sub   r12, 2          ; r12 = 2n - 2   (Последняя диагональ = k=2n-2)

    ; k => r13
    xor   r13, r13        ; k=0

.diag_loop:
    ; Если k > (2n - 2), выходим (используем jg чтобы обрабатывать k=2n-2 включительно)
    cmp   r13, r12
    jg    .done_diags

    ; -----------------------------------------------------
    ; Определить длину диагонали (diag_len) => rdi
    ;   если k < n => diag_len = k + 1
    ;   иначе      => diag_len = (2n - 2) - k + 1
    ;   (ранее было 2n-1 - k, теперь 2n-2 => нужно +1)
    ; -----------------------------------------------------
    xor   rdi, rdi
    cmp   r13, r8
    jl    .case_k_less

    ; k >= n
    ; diag_len = (2n-2) - k + 1 = 2n-1 - k
    mov   rdi, r12    ; rdi = 2n-2
    sub   rdi, r13    ; (2n-2) - k
    inc   rdi         ; +1
    jmp   .diag_len_ready

.case_k_less:
    mov   rdi, r13
    inc   rdi         ; diag_len = k+1

.diag_len_ready:
    ; rdi = diag_len

    ; 2) Сбор элементов diag => diag_buffer
    mov   rsi, diag_buffer
    xor   rdx, rdx        ; rdx=0 (индекс в буфере)
    xor   rax, rax        ; rax=0 (row=0)

.collect_loop:
    cmp   rax, r8
    jge   .collect_done

    ; col = k - row  (k => r13)
    mov   rcx, r13
    sub   rcx, rax

    ; Проверка col в [0..n)
    cmp   rcx, r8
    jae   .skip_collect
    cmp   rcx, 0
    jl    .skip_collect

    ; index=(row*n + col)*8
    mov   r9, r8
    imul  r9, rax
    add   r9, rcx
    shl   r9, 3
    mov   r10, matrix
    add   r10, r9
    mov   r11, [r10]

    mov   [rsi + rdx*8], r11
    inc   rdx

.skip_collect:
    inc   rax
    jmp   .collect_loop

.collect_done:
    cmp   rdi, 1
    jle   .no_sort_needed

    ; 3) Сортировка вставками + бинарный поиск
    xor   rax, rax
    mov   rax, 1   ; i=1

.sort_outer:
    cmp   rax, rdi
    jge   .done_insertion

    ; current_value => rbx
    mov   rbx, [rsi + rax*8]

    ; Бинарный поиск => left=0(rcx), right=i(r9)
    xor   rcx, rcx
    mov   r9, rax

.binsearch_loop:
    cmp   rcx, r9
    jge   .binsearch_end

    mov   r10, rcx
    add   r10, r9
    shr   r10, 1
    mov   r11, [rsi + r10*8]

    ; Проверка sortDirection
    mov   al, [sortDirection]
    cmp   al, 1
    jne   .descending

    ; ---- Возрастание ----
    cmp   r11, rbx
    jle   .go_right     ; если diag_buffer[mid] <= currVal => left=mid+1
    mov   r9, r10       ; right=mid
    jmp   .binsearch_loop

.descending:
    ; ---- Убывание ----
    cmp   r11, rbx
    jge   .go_right     ; если diag_buffer[mid] >= currVal => left=mid+1
    mov   r9, r10       ; right=mid
    jmp   .binsearch_loop

.go_right:
    inc   r10
    mov   rcx, r10
    jmp   .binsearch_loop

.binsearch_end:
    ; pos => r10
    mov   r10, rcx

    ; Сдвиг [pos.. i-1] на 1 вправо
    ; j = i-1 => используем r14, не трогаем r8=n
    mov   r14, rax
    dec   r14

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

    ; 4) Возвращаем отсортированный diag => matrix
    xor   rax, rax   ; row=0
    xor   rcx, rcx   ; индекс в diag_buffer=0

.return_loop:
    cmp   rax, r8
    jge   .return_done

    mov   r9, r13     ; col = k - row
    sub   r9, rax
    cmp   r9, r8
    jae   .ret_skip
    cmp   r9, 0
    jl    .ret_skip

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
    ; 5) exit(0)
    mov   rax, 60
    xor   rdi, rdi
    syscall
