;; Testing framework (from practical common lisp)
(defmacro with-gensyms ((&rest names) &body body)
  `(let ,(loop for n in names collect `(,n (gensym)))
     ,@body))

(defvar *test-name* nil)

(defmacro deftest (name parameters &body body)
  "Define a test function. Within a test function we can call
   other test functions or use 'check' to run individual test
   cases."
  `(defun ,name ,parameters
     (let ((*test-name* (append *test-name* (list ',name))))
       ,@body)))

(defmacro check (&body forms)
  "Run each expression in 'forms' as a test case."
  `(combine-results
    ,@(loop for f in forms collect `(report-result ,f ',f))))

(defmacro combine-results (&body forms)
  "Combine the results (as booleans) of evaluating 'forms' in order."
  (with-gensyms (result)
    `(let ((,result t))
       ,@(loop for f in forms collect `(unless ,f (setf ,result nil)))
       ,result)))

(defun report-result (result form)
  "Report the results of a single test case. Called by 'check'."
  (format t "~:[FAIL~;pass~] ... ~a: ~a~%" result *test-name* form)
  result)

;; Vector math
(defun invert-vec (v)
  (destructuring-bind (x y z) v
    (list (- x) (- y) (- z))))

(defun magnitude (v)
  (destructuring-bind (x y z) v
    (sqrt (+ (* x x) (* y y) (* z z)))))

(defun square-magnitude (v)
  (destructuring-bind (x y z) v
    (+ (* x x) (* y y) (* z z))))

(defun normalize (v)
  (let ((l (magnitude v)))
    (destructuring-bind (x y z) v
      (list (/ x l) (/ y l) (/ z l)))))

(defun scale-vec (v s)
  (destructuring-bind (x y z) v
    (list (* x s) (* y s) (* z s))))

(defun add-vec (v1 v2)
  (destructuring-bind (x1 y1 z1) v1
    (destructuring-bind (x2 y2 z2) v2
      (list (+ x1 x2) (+ y1 y2) (+ z1 z2)))))

(defun sub-vec (v1 v2)
  (destructuring-bind (x1 y1 z1) v1
    (destructuring-bind (x2 y2 z2) v2
      (list (- x1 x2) (- y1 y2) (- z1 z2)))))

(defun add-scaled-vec (v1 v2 s)
  (add-vec v1 (scale-vec v2 s)))

(defun component-product (v1 v2)
  (destructuring-bind (x1 y1 z1) v1
    (destructuring-bind (x2 y2 z2) v2
      (list (* x1 x2) (* y1 y2) (* z1 z2)))))

(defun scalar-product (v1 v2)
  (destructuring-bind (x1 y1 z1) v1
    (destructuring-bind (x2 y2 z2) v2
      (+ (* x1 x2) (* y1 y2) (* z1 z2)))))

(defun vector-product (v1 v2)
  (destructuring-bind (x1 y1 z1) v1
    (destructuring-bind (x2 y2 z2) v2
      (list (- (* y1 z2) (* z1 y2))
            (- (* z1 x2) (* x1 z2))
            (- (* x1 y2) (* y1 x2))))))

;; (deftest test-invert-vec ()
;;   (check
;;     (= )))

(defclass physical-particle ()
  ((particle-position
    :initarg :position
    :initform '(0 0 0)
    :accessor particle-position)
   (velocity
    :initarg :velocity
    :initform '(0 0 0)
    :accessor velocity)
   (acceleration
    :initarg :acceleration
    :initform '(0 0 0)
    :accessor acceleration)
   (force-accum
    :initform '(0 0 0)
    :accessor force-accum)
   (damping
    :initarg :damping
    :initform 0.999
    :accessor damping)
   (inverse-mass
    :initform 0
    :accessor inverse-mass)))

(defun has-finite-mass (particle)
  (plusp (inverse-mass particle)))

(defgeneric mass (particle)
  (:documentation "Read the mass value of a particle."))

(defmethod mass ((particle physical-particle))
  (with-slots (inverse-mass) particle
    (if (zerop inverse-mass)
        :positive-infinity
        (/ 1 inverse-mass))))

(defgeneric (setf mass) (value particle)
  (:documentation "Set the mass value of a particle."))

(defmethod (setf mass) (value (particle physical-particle))
  (setf (slot-value particle 'inverse-mass) (/ 1 value)))

(defmethod initialize-instance :after ((particle physical-particle)
                                       &key mass)
  (when mass
      (setf (mass particle) mass)))

(defgeneric clear-accumulator (particle)
  (:documentation "Remove acting forces from a particle."))

(defmethod clear-accumulator ((particle physical-particle))
  (with-slots (force-accum) particle
    (setf force-accum '(0 0 0))))

(defgeneric integrate-particle (particle duration))

(defmethod integrate-particle ((particle physical-particle) duration)
  ;; Don't integrate things with infinite mass.
  (when (plusp (slot-value particle 'inverse-mass))
    (assert (plusp duration))
    (with-accessors ((pos particle-position)
                     (velocity velocity)
                     (acceleration acceleration)
                     (damping damping)
                     (force-accum force-accum)
                     (inverse-mass inverse-mass)) particle
      ;; Update linear position.
      (setf pos (add-scaled-vec pos velocity duration))
      ;; Work out the acceleration from the force.
      ;; (We'll add to this when we come to generate forces...)
      (let ((resulting-acc (add-scaled-vec acceleration
                                           force-accum
                                           inverse-mass)))
        ;; Update linear velocity from the acceleration.
        (setf velocity (add-scaled-vec velocity resulting-acc duration)))
      ;; Impose drag.
      (setf velocity (scale-vec velocity (expt damping duration)))
      ;; Clear the forces
      (clear-accumulator particle))))

(defgeneric add-force (particle force)
  (:documentation "Adds the given force to be applied to the particle at the next iteration only"))

(defmethod add-force ((particle physical-particle) force)
  (with-slots (force-accum) particle
    (setf force-accum (add-vec force-accum force))))

(defparameter *particle-force-registry*
  (make-array 0 :adjustable t))

(defun add-force-generator (force-generator particle)
  (vector-push-extend (list force-generator particle)
                      *particle-force-registry*))

(defun update-forces (duration)
  (loop for (force-generator particle) across *particle-force-registry*
     do (funcall force-generator particle duration)))

(defun particle-gravity (gravity)
  (lambda (particle duration)
    (declare (ignore duration))
    (when (has-finite-mass particle)
      (add-force particle (scale-vec (mass particle) gravity)))))

(defun particle-drag (k1 k2)
  (lambda (particle duration)
    (declare (ignore duration))
    (with-accessors ((velocity velocity)) particle
      (let* ((speed (magnitude velocity))
             (drag-coeff (+ (* k1 speed) (* k2 speed speed))))
        (add-force particle
                   (scale-vec (normalize velocity)
                              (- drag-coeff)))))))

(defun spring-force (pos1 pos2 spring-constant rest-length)
  (let* ((distance (sub-vec pos1 pos2))
         (mag (* (abs (- (magnitude distance) rest-length))
                 spring-constant
                 -1)))
    (scale-vec (normalize distance) mag)))

(defun particle-spring (other spring-constant rest-length)
  (lambda (particle duration)
    (declare (ignore duration))
    (add-force particle
               (spring-force (particle-position particle)
                             (particle-position other)
                             spring-constant
                             rest-length))))

(defun particle-anchored-spring (anchor spring-constant rest-length)
  (lambda (particle duration)
    (declare (ignore duration))
    (add-force particle
               (spring-force (particle-position particle)
                             anchor
                             spring-constant
                             rest-length))))

(defun particle-buoyancy (max-depth volume water-height
                          &optional (liquid-density 1000))
  (lambda (particle duration)
    (declare (ignore duration))
    (destructuring-bind (x y z) (particle-position particle)
      (declare (ignore x z))
      (let ((depth y))
        (add-force particle
                   (list 0
                         (if (>= depth (+ water-height max-depth))
                             (* liquid-density volume)
                             (* liquid-density
                                volume
                                (/ (- depth max-depth water-height) 2)
                                max-depth))
                         0))))))

(defun particle-fake-spring (anchor spring-constant damping)
  (lambda (particle duration)
    (when (has-finite-mass particle)
      (let ((delta-position (sub-vec (particle-position particle)
                                     anchor))
            (gamma (* 0.5 (sqrt (- (* 4 spring-constant)
                                   (* damping damping))))))
        (when (not (zerop gamma))
          (let* ((c (add-vec (scale-vec delta-position (/ damping 2 gamma))
                             (scale-vec (velocity particle) (/ 1 gamma))))
                 (target (scale-vec
                          (add-vec (scale-vec delta-position
                                              (cos (* gamma duration)))
                                   (scale-vec c (sin (* gamma duration))))
                          (exp (* -0.5 duration damping))))
                 (accel (sub-vec (scale-vec (sub-vec target delta-position)
                                            (/ 1 (* duration duration)))
                                 (scale-vec (velocity particle) duration))))
            (add-force particle (scale-vec accel (mass particle)))))))))
