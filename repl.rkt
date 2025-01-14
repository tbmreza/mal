#lang racket

(require "reader.rkt")
(require "printer.rkt")
(require "env.rkt")

(define-namespace-anchor a)
(define ns (namespace-anchor->namespace a))

(define READ read-mal-syntax)

(define variable-name? symbol?)

(define (interpret env ast)
  (match ast
    [keyword
      #:when (member keyword `(true false))
      (eval keyword ns)]

    [keyword
      #:when (member keyword `(nil))
      (eval '(void) ns)]

    [(? variable-name? var)  (env-get env var)]
    [`(lambda ,_ ,_)         ast]

    [(? list? nodes)
     (map (lambda (node) (eval/p env node))
          nodes)]

    [value value]))

(define (filter-when pred? lst)
  (for/list ([i (length lst)] #:when (pred? i))
    (list-ref lst i)))

(define (eval/p env ast)
  (cond [(not (list? ast))  (interpret env ast)]
        [(empty? ast)       ast]
        [else
          (match (car ast)
            ['list  (interpret env (cdr ast))]

            ['def!
             (let ([k  (first (cdr ast))]
                   [v  (eval/p env (second (cdr ast)))])
               (env-set! env k v) v)]

            ['let*
             (let* ([bindings       (second ast)]
                    [binding-vars   (filter-when even? bindings)]
                    [binding-exprs  (filter-when odd? bindings)]
                    [env+           (env-nest env binding-vars binding-exprs)]
                    [body           (third ast)])
               (eval/p env+ body))]

            ['if
             (cond [(eval/p env (second ast))  (eval/p env (third ast))]
                   [else                       (eval/p env (fourth ast))])]

            ['do  (last (interpret env (cdr ast)))]

            ['fn*
             (let* ([binding-vars  (second ast)]
                    [body          (third ast)]
                    [f             `(lambda ,(values binding-vars) ,body)])
               ; Defer nesting env because binding-exprs is only available on fn* application.
               (eval/p env f))]

            [_
              (match ast
                [`(lambda ,_ ,_)  (eval ast ns)]
                [_
                  (let* ([nodes  (interpret env ast)]
                         [proc   (car nodes)]
                         [args   (cdr nodes)])
                    (match proc
                      [`(lambda ,binding-vars ,body)
                        (eval/p (env-nest env binding-vars args) body)]
                      [_  (apply proc args)]))])])]))

;; EVAL :: ast -> <unit or any>
(define EVAL
  ((curry eval/p) repl-env))

(define PRINT pr-str)

(define rep (compose1 PRINT EVAL READ))

(define (silence go) (begin go (void)))
(define exec (compose1 silence EVAL READ))

; core.rkt {
(silence (env-set! repl-env 'eval (lambda (ast) (EVAL repl-env ast))))
; }

;; (define exec-lines)
;; (exec-lines "core.mal")
; core.mal {  ?? rep defs and repl is separate modules. repl.rkt reads core.mal line by line before it starts looping
(exec "(def! not (fn* (a) (if a #f #t)))")

; Use racket's here string to sidestep escaping " and \ literals.
(exec #<<unnamed
(def! load-file (fn* (f) (eval (read-string (str "(do " (slurp f) "\nnil)")))))
unnamed
)
; }

(require readline/readline)

(define (repl-loop)  ; ?? panics on user break. turnt sets return_code = 1. <c-z> is fine though
  (let ([line (readline "user> ")])
    (add-history line)
    (rep line))
  (repl-loop))

(module+ main (repl-loop))

(module+ test (require rackunit)
;;   (define prog #<<unnamed
;; (load-file "./input.mal")
;; unnamed
;; )
;; ;; ;; ok:
;; ;;   (define prog #<<unnamed
;; ;; (not true)
;; ;; unnamed
;; ;; )
;;   (rep prog)

  (check-eq?
    "do slurp terminates"
    (eval/p repl-env '(load-file "./input.mal")))

  (check-eq?
    "do slurp terminates"
    (eval/p repl-env '(do (slurp "input.mal") "do slurp terminates")))

  (check-eq?
    2
    (eval/p repl-env '(+ 1 1)))

  ;; (displayln 12)
  )
