section .data

    ; Размер матрицы (1 байт, до 255).
    n db 4

    ; Квадратная матрица 4x4, 64-битные элементы (dq).
    matrix dq  9,  3,  1,  7
           dq 12,  4,  0,  2
           dq 11, 10,  6,  8
           dq 15, 14, 13,  5

    ; Выбор направления сортировки:
    ;   1 => по возрастанию
    ;  -1 => по убыванию (или любое значение, не равное 1)
    sortDirection db 1

section .bss

    ; Буфер для одной диагонали (до 255 элементов * 8 байт).
    diag_buffer resb 2048

section .text
global _start

; ---------------------------------------------------------
; _start — точка входа
;  1) Считать n в r8 (значение n не трогаем далее).
;  2) Храним номер диагонали k в r13 (k = 0..(2n-2)).
;  3) Для каждой диагонали собираем элементы в diag_buffer.
;  4) Сортируем собранную диагональ методом вставками с бинарным поиском,
;     учитывая значение sortDirection.
;  5) Возвращаем отсортированную диагональ обратно в matrix.
;  6) Выход (syscall exit(0)).
; ---------------------------------------------------------
_start:
    ; 1) Считать n (1 байт) и сохранить в r8.
    movzx rax, byte [n]
    mov   r8, rax         ; r8 = n

    ; Вычисляем (2n - 2) заранее и сохраняем в r12 (конечное значение k).
    mov   r12, r8
    shl   r12, 1          ; r12 = 2*n
    sub   r12, 2          ; r12 = 2n - 2

    ; 2) k = 0..(2n-2) храним в r13.
    xor   r13, r13        ; r13 = 0

.diag_loop:
    ; Если k > (2n - 2), завершаем обработку диагоналей.
    cmp   r13, r12
    jg    .done_diags

    ; -----------------------------------------------------
    ; Определяем длину диагонали (diag_len) и сохраняем в rdi.
    ; Если k < n, то diag_len = k + 1.
    ; Если k >= n, то diag_len = (2n - 2 - k) + 1 = 2n - 1 - k.
    ; -----------------------------------------------------
    xor   rdi, rdi
    cmp   r13, r8
    jl    .case_k_less
    ; k >= n:
    mov   rdi, r12        ; rdi = 2n - 2
    sub   rdi, r13        ; rdi = (2n - 2) - k
    inc   rdi             ; diag_len = (2n - 2 - k) + 1 = 2n - 1 - k
    jmp   .diag_len_ready
.case_k_less:
    mov   rdi, r13        ; rdi = k
    inc   rdi             ; diag_len = k + 1
.diag_len_ready:
    ; rdi = diag_len

    ; -----------------------------------------------------
    ; Собираем элементы текущей диагонали (где row + col = k) в diag_buffer.
    ; row хранится в rax (0..n-1), col = k - row.
    ; Результат сохраняется в diag_buffer, индекс в нем – rdx.
    ; -----------------------------------------------------
    mov   rsi, diag_buffer
    xor   rdx, rdx        ; rdx = 0
    xor   rax, rax        ; row = 0

.collect_loop:
    cmp   rax, r8
    jge   .collect_done

    ; Вычисляем col = k - row; k хранится в r13.
    mov   rcx, r13
    sub   rcx, rax

    ; Проверяем, что col находится в пределах [0, n).
    cmp   rcx, r8
    jae   .skip_collect
    cmp   rcx, 0
    jl    .skip_collect

    ; Вычисляем индекс элемента в matrix: (row*n + col)*8.
    mov   r9, r8
    imul  r9, rax        ; r9 = row * n
    add   r9, rcx        ; r9 = row*n + col
    shl   r9, 3          ; умножаем на 8 (размер элемента dq)
    mov   r10, matrix
    add   r10, r9        ; r10 = адрес matrix[row, col]
    mov   r11, [r10]     ; читаем элемент

    ; Записываем элемент в diag_buffer[rdx].
    mov   [rsi + rdx*8], r11
    inc   rdx

.skip_collect:
    inc   rax           ; row++
    jmp   .collect_loop

.collect_done:
    ; Если diag_len <= 1, сортировка не требуется.
    cmp   rdi, 1
    jle   .no_sort_needed

    ; -----------------------------------------------------
    ; Сортировка вставками с бинарным поиском.
    ; Диапазон для сортировки: diag_buffer[0..diag_len-1]
    ; -----------------------------------------------------
    xor   rax, rax
    mov   rax, 1        ; i = 1

.sort_outer:
    cmp   rax, rdi
    jge   .done_insertion

    ; current_value = diag_buffer[i] -> сохраняем в rbx.
    mov   rbx, [rsi + rax*8]

    ; Бинарный поиск: ищем позицию для current_value в отсортированной части diag_buffer[0..i-1].
    ; left = 0 (rcx), right = i (r9).
    xor   rcx, rcx      ; left = 0
    mov   r9, rax       ; right = i
    mov   r15, -1       ; инициализируем предыдущий mid для защиты от бесконечного цикла

.binsearch_loop:
    cmp   rcx, r9
    jge   .binsearch_end

    mov   r10, rcx
    add   r10, r9
    shr   r10, 1       ; mid = (left+right)/2

    ; Защитное условие: если mid не изменился, выходим.
    cmp   r15, r10
    je    .binsearch_end
    mov   r15, r10

    mov   r11, [rsi + r10*8]  ; diag_buffer[mid]
    mov   al, [sortDirection]
    cmp   al, 1
    jne   .descending
    ; -------- Возрастание --------
    cmp   r11, rbx
    jle   .go_right       ; если diag_buffer[mid] <= current_value, left = mid+1
    mov   r9, r10         ; иначе right = mid
    jmp   .binsearch_loop

.descending:
    ; -------- Убывание --------
    cmp   r11, rbx
    jge   .go_right       ; если diag_buffer[mid] >= current_value, left = mid+1
    mov   r9, r10         ; иначе right = mid
    jmp   .binsearch_loop

.go_right:
    inc   r10
    mov   rcx, r10        ; left = mid+1
    jmp   .binsearch_loop

.binsearch_end:
    ; Позиция для вставки = left (rcx); сохраняем её в r10.
    mov   r10, rcx

    ; Сдвигаем элементы из диапазона [pos, i-1] на 1 вправо.
    ; Для этого используем r14 как счётчик, чтобы не затирать r8.
    mov   r14, rax
    dec   r14             ; r14 = i - 1

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
    ; Возвращаем отсортированную диагональ обратно в matrix.
    ; Для каждой строки row (0..n-1) вычисляем col = k - row.
    ; Если col находится в [0, n), записываем diag_buffer[rcx] в matrix[row, col].
    ; -----------------------------------------------------
    xor   rax, rax    ; row = 0
    xor   rcx, rcx    ; индекс diag_buffer = 0

.return_loop:
    cmp   rax, r8
    jge   .return_done

    mov   r9, r13     ; r9 = k (из r13)
    sub   r9, rax     ; r9 = k - row  (то есть col)
    cmp   r9, r8
    jae   .ret_skip
    cmp   r9, 0
    jl    .ret_skip

    mov   r10, r8
    imul  r10, rax    ; r10 = row * n
    add   r10, r9     ; r10 = row*n + col
    shl   r10, 3      ; r10 *= 8
    mov   r11, matrix
    add   r11, r10

    mov   r14, [rsi + rcx*8]
    mov   [r11], r14
    inc   rcx

.ret_skip:
    inc   rax
    jmp   .return_loop

.return_done:

    ; -----------------------------------------------------
    ; Завершаем обработку диагоналей: k++
    inc   r13
    jmp   .diag_loop

.done_diags:
    ; -----------------------------------------------------
    ; Вызываем syscall exit(0)
    mov   rax, 60
    xor   rdi, rdi
    syscall
