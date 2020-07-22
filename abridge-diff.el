(defvar abridge-diff-word-buffer 6
  "Number of words to preserve around refined regions.")

(defvar abridge-diff-invisible-min 5
  "Minimum region length between refine areas that can be made invisible.")

(defvar abridge-diff-no-change-line-words 12
  "Number of words to keep at the beginning of a line without any refined diffs.")

(defvar abridge-diff-first-words-preserve 4
  "Keep at least this many words visible at the beginning of an abridged line with refined diffs.")

(defun abridge-diff-merge-exclude (excludes)
  (let ((p excludes))
    (while (cdr p)
      (let ((left (car p))
	    (right (cadr p)))
	(if (>= (- (car right) (cadr left)) abridge-diff-invisible-min)
	    (setq p (cdr p))
	  (setcar p (list (car left) (cadr right)))
	  (setcdr p (cddr p)))))))

(defun abridge-diff-compute-hidden (beg end excludes)
  "Compute a list of ranges (from to) between position beg and end, 
skipping the ranges listed in EXCLUDES"
  (let ((hide (list (list beg (caar excludes))))
	(p excludes))
    (while (cdr p)
      (let ((left (car p))
	    (right (cadr p)))
	(push (list (cadr left) (car right)) hide)
	(setq p (cdr p))))
    (push (list (cadr (car (last excludes))) end) hide)
    (seq-filter (lambda (range)
		  (> (- (cadr range) (car range))
		     abridge-diff-invisible-min))
		(nreverse hide))))

(defun abridge-diff-make-invisible (beg end)
  (if (> (- end beg) abridge-diff-invisible-min)
      (let ((protect
	     (mapcar (lambda (ov)
		       (let ((ovbeg (overlay-start ov))
			     (ovend (overlay-end ov))
			     pbeg pend)
			 (save-excursion
			   (goto-char ovbeg)
			   (backward-word abridge-diff-word-buffer)
			   (setq pbeg (max beg (point)))
			   (goto-char ovend)
			   (forward-word abridge-diff-word-buffer)
			   (setq pend (min end (point))))
			 (list pbeg pend)))
		     (sort 
		      (seq-filter (lambda (ov)
				    (eq (overlay-get ov 'diff-mode) 'fine))
				  (overlays-in beg end))
		      (lambda (a b) (< (overlay-start a) (overlay-start b))))))
	    hide)
	
	(if (memq (char-after beg) '(?+ ?-))
	    (setq beg (1+ beg)))

	

	(if (not protect) ;nothing specific changed, just show first words
	    (setq hide (list (list
			      (save-excursion
				(goto-char beg)
				(forward-word abridge-diff-no-change-line-words)
				(min (point) end))
			      end)))
	  (save-excursion
	    (goto-char beg)
	    (forward-word abridge-diff-first-words-preserve)
	    (push (list beg (min end (point))) protect))
	  (abridge-diff-merge-exclude protect)
	  (setq hide (abridge-diff-compute-hidden beg end protect)))

	(dolist (range hide)
	  (add-text-properties (car range) (cadr range)
			       '(invisible abridge-diff-invisible))))))

(defun abridge-diff-mark (&rest rest)
  (dolist (x (seq-partition (seq-take rest 4) 2))
    (save-excursion
      (goto-char (car x))
      (while (< (point) (cadr x))
	(abridge-diff-make-invisible (point) (line-end-position))
	(forward-line)))))

(advice-add #'smerge-refine-regions :after #'abridge-diff-mark)

(defun abridge-diff-enable-hiding ()
  (interactive)
  (add-to-invisibility-spec '(abridge-diff-invisible . t)))
(add-hook 'magit-diff-mode-hook #'abridge-diff-enable-hiding)

(defun abridge-diff-disable-hiding ()
  (interactive)
  (setq buffer-invisibility-spec nil))

(defun abridge-diff-toggle-hiding ()
  (interactive)
  (if buffer-invisibility-spec
      (abridge-diff-disable-hiding)
    (abridge-diff-enable-hiding)))

(require 'magit-diff)
(transient-append-suffix 'magit-diff-refresh 'magit-diff-toggle-refine-hunk
  '("a" "abridge refined diffs" abridge-diff-toggle-hiding))

;(advice-remove #'smerge-refine-regions #'abridge-diff-mark)

