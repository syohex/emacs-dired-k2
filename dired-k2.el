;;; dired-k2.el --- highlight dired buffer by file size, modified time, git status -*- lexical-binding: t; -*-

;; Copyright (C) 2020 by Shohei YOSHIDA

;; Author: Syohei YOSHIDA <syohex@gmail.com>
;; URL: https://github.com/syohex/emacs-dired-k2
;; Version: 0.19
;; Package-Requires: ((emacs "26.1"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides highlighting dired buffer like k.sh which is
;; zsh script.
;;
;; Example usage:
;;
;;   (require 'dired-k2)
;;   (define-key dired-mode-map (kbd "K") #'dired-k2)
;;

;;; Code:

(require 'cl-lib)
(require 'dired)

(defgroup dired-k2 nil
  "k.sh in dired"
  :group 'dired)

(defface dired-k2-modified
  '((t (:foreground "red" :weight bold)))
  "Face of modified file in git repository")

(defface dired-k2-commited
  '((t (:foreground "green" :weight bold)))
  "Face of commited file in git repository")

(defface dired-k2-added
  '((t (:foreground "magenta" :weight bold)))
  "Face of added file in git repository")

(defface dired-k2-untracked
  '((t (:foreground "orange" :weight bold)))
  "Face of untracked file in git repository")

(defface dired-k2-ignored
  '((t (:foreground "cyan" :weight bold)))
  "Face of ignored file in git repository")

(defface dired-k2-directory
  '((t (:foreground "blue")))
  "Face of directory")

(defface dired-k2--dummy
  '((((class color) (background light))
     (:background "red"))
    (((class color) (background dark))
     (:background "blue")))
  "Don't use this theme")

(defsubst dired-k2--light-p ()
  (string= (face-background 'dired-k2--dummy) "red"))

(defcustom dired-k2-size-colors
  '((1024 . "chartreuse4") (2048 . "chartreuse3") (3072 . "chartreuse2")
    (5120 . "chartreuse1") (10240 . "yellow3") (20480 . "yellow2") (40960 . "yellow")
    (102400 . "orange3") (262144 . "orange2") (524288 . "orange"))
  "assoc of file size and color"
  :type '(repeat (cons (integer :tag "File size")
                       (string :tag "Color"))))

(defcustom dired-k2-date-colors
  (if (dired-k2--light-p)
      '((0 . "red") (60 . "grey0") (3600 . "grey10")
        (86400 . "grey25") (604800 . "grey40") (2419200 . "grey40")
        (15724800 . "grey50") (31449600 . "grey65") (62899200 . "grey85"))
    '((0 . "red") (60 . "white") (3600 . "grey90")
      (86400 . "grey80") (604800 . "grey65") (2419200 . "grey65")
      (15724800 . "grey50") (31449600 . "grey45") (62899200 . "grey35")))
  "assoc of file modified time and color"
  :type '(repeat (cons (integer :tag "Elapsed seconds from last modified")
                       (string :tag "Color"))))

(defsubst dired-k2--git-status-color (stat)
  (cl-case stat
    (modified 'dired-k2-modified)
    (normal 'dired-k2-commited)
    (added 'dired-k2-added)
    (untracked 'dired-k2-untracked)
    (ignored 'dired-k2-ignored)))

(defsubst dired-k2--decide-status (status)
  (cond ((string= status " M") 'modified)
        ((string= status "??") 'untracked)
        ((string= status "!!") 'ignored)
        ((string= status "A ") 'added)
        (t 'normal)))

(defsubst dired-k2--subdir-status (current-status new-status)
  (cond ((eq current-status 'modified) 'modified)
        ((eq new-status 'added) 'added)
        ((not current-status) new-status)
        (t current-status)))

(defun dired-k2--is-in-child-directory (here path)
  (let ((relpath (file-relative-name path here)))
    (string-match-p "/" relpath)))

(defun dired-k2--child-directory (here path)
  (let ((regexp (concat here "\\([^/]+\\)")))
    (when (string-match regexp path)
      (concat here (match-string-no-properties 1 path)))))

(defun dired-k2--fix-up-filename (file)
  ;; If file name contains spaces, then it is wrapped double quote.
  (if (string-match "\\`\"\\(.+\\)\"\\'" file)
      (match-string-no-properties 1 file)
    file))

(defun dired-k2--parse-git-status (root proc deep)
  (with-current-buffer (process-buffer proc)
    (goto-char (point-min))
    (let ((files-status (make-hash-table :test 'equal))
          (here (expand-file-name default-directory)))
      (while (not (eobp))
        (let* ((line (buffer-substring-no-properties
                      (line-beginning-position) (line-end-position)))
               (status (dired-k2--decide-status (substring line 0 2)))
               (file (substring line 3))
               (full-path (concat root (dired-k2--fix-up-filename file))))
          (when (and (not deep) (dired-k2--is-in-child-directory here full-path))
            (let* ((subdir (dired-k2--child-directory here full-path))
                   (status (if (and (eq status 'ignored) (not (file-directory-p full-path)))
                               'normal
                             status))
                   (cur-status (gethash subdir files-status)))
              (puthash subdir (dired-k2--subdir-status cur-status status)
                       files-status)))
          (puthash full-path status files-status))
        (forward-line 1))
      files-status)))

(defsubst dired-k2--process-buffer ()
  (get-buffer-create (format "*dired-k2-%s*" dired-directory)))

(defun dired-k2--start-git-status (cmds root proc-buf callback)
  (let ((curbuf (current-buffer))
        (deep (not (eq major-mode 'dired-mode)))
        (old-proc (get-buffer-process proc-buf)))
    (when (and old-proc (process-live-p old-proc))
      (kill-process old-proc)
      (unless (buffer-live-p proc-buf)
        (setq proc-buf (dired-k2--process-buffer))))
    (with-current-buffer proc-buf
      (erase-buffer))
    (let ((proc (apply 'start-file-process "dired-k2-git-status" proc-buf cmds)))
      (set-process-query-on-exit-flag proc nil)
      (set-process-sentinel
       proc
       (lambda (proc _event)
         (when (eq (process-status proc) 'exit)
           (if (/= (process-exit-status proc) 0)
               (message "Failed: %s" cmds)
             (when (buffer-live-p (process-buffer proc))
               (let ((stats (dired-k2--parse-git-status root proc deep)))
                 (funcall callback stats curbuf)
                 (kill-buffer proc-buf))))))))))

(defsubst dired-k2--root-directory ()
  (locate-dominating-file default-directory ".git/"))

(defun dired-k2--highlight-line-normal (stat)
  (let ((ov (make-overlay (1- (point)) (point)))
        (stat-face (dired-k2--git-status-color stat))
        (sign (if (memq stat '(modified added)) "+" "|")))
    (overlay-put ov 'display
                 (propertize sign 'face stat-face))))

(defun dired-k2--highlight-line (file stats)
  (let ((stat (gethash file stats 'normal)))
    (dired-k2--highlight-line-normal stat)))

(defsubst dired-k2--directory-end-p ()
  (let ((line (buffer-substring-no-properties
               (line-beginning-position) (line-end-position))))
    (string-match-p "\\`\\s-*\\'" line)))

(defsubst dired-k2--move-to-next-directory ()
  (dired-next-subdir 1 t)
  (dired-next-line 2))

(defun dired-k2--highlight-git-information (stats buf)
  (if (not (buffer-live-p buf))
      (message "Buffer %s no longer lives" buf)
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        (dired-next-line 2)
        (while (not (eobp))
          (let ((filename (dired-get-filename nil t)))
            (when (and filename (not (string-match-p "/\\.?\\.\\'" filename)))
              (dired-k2--highlight-line filename stats)))
          (dired-next-line 1)
          (when (dired-k2--directory-end-p)
            (dired-k2--move-to-next-directory)))))))

(defsubst dired-k2--size-face (size)
  (cl-loop for (border . color) in dired-k2-size-colors
           when (< size border)
           return `((:foreground ,color :weight bold))
           finally
           return '((:foreground "red" :weight bold))))

(defsubst dired-k2--date-face (modified-time)
  (cl-loop with current-time = (float-time (current-time))
           with diff = (- current-time modified-time)
           for (val . color) in dired-k2-date-colors
           when (< diff val)
           return `((:foreground ,color :weight bold))
           finally
           return '((:foreground "grey50" :weight bold))))

(defun dired-k2--highlight-by-size (size start end)
  (let ((ov (make-overlay start end))
        (size-face (dired-k2--size-face size)))
    (overlay-put ov 'face size-face)))

(defun dired-k2--highlight-by-date (modified-time start end)
  (let* ((ov (make-overlay start end))
         (size-face (dired-k2--date-face (float-time modified-time))))
    (overlay-put ov 'face size-face)))

(defsubst dired-k2--size-to-regexp (size)
  (concat "\\_<" (number-to-string size) "\\_>"))

(defun dired-k2--highlight-directory ()
  (save-excursion
    (back-to-indentation)
    (when (eq (char-after) ?d)
      (let ((ov (make-overlay (point) (1+ (point)))))
        (overlay-put ov 'face 'dired-k2-directory)))))

(defun dired-k2--move-to-file-size-column ()
  (goto-char (line-beginning-position))
  (dotimes (_i 4)
    (skip-chars-forward " ")
    (skip-chars-forward "^ "))
  (skip-chars-forward " "))

(defun dired-k2--highlight-by-file-attribyte ()
  (save-excursion
    (goto-char (point-min))
    (dired-next-line 2)
    (while (not (eobp))
      (let* ((file-attrs (file-attributes (dired-get-filename nil t)))
             (modified-time (nth 5 file-attrs))
             (file-size (nth 7 file-attrs))
             (date-end-point (1- (point))))
        (dired-k2--highlight-directory)
        (when file-size
          (when (re-search-backward (dired-k2--size-to-regexp file-size) nil t)
            (dired-k2--highlight-by-size file-size (match-beginning 0) (match-end 0)))
          (skip-chars-forward "^ \t")
          (skip-chars-forward " \t")
          (dired-k2--highlight-by-date modified-time (point) date-end-point))
        (dired-next-line 1)
        (when (dired-k2--directory-end-p)
          (dired-k2--move-to-next-directory))))))

(defun dired-k2--inside-git-repository-p ()
  (with-temp-buffer
    (when (zerop (process-file "git" nil t nil "rev-parse" "--is-inside-work-tree"))
      (goto-char (point-min))
      (string= "true" (buffer-substring-no-properties
                       (point) (line-end-position))))))

(defun dired-k2--highlight (revert)
  (when revert
    (revert-buffer nil t))
  (save-excursion
    (dired-k2--highlight-by-file-attribyte)
    (when (dired-k2--inside-git-repository-p)
      (let ((root (dired-k2--root-directory)))
        (when root
          (dired-k2--start-git-status
           '("git" "status" "--porcelain" "--ignored" "--untracked-files=normal" ".")
           (expand-file-name root) (dired-k2--process-buffer)
           #'dired-k2--highlight-git-information))))))

;;;###autoload
(defun dired-k2-no-revert ()
  "Same as `dired-k2' except not calling `revert-buffer'."
  (interactive)
  (dired-k2--highlight nil))

;;;###autoload
(defun dired-k2 ()
  "Highlighting dired buffer by file size, last modified time, and git status.
This is inspired by `k' zsh script"
  (interactive)
  (dired-k2--highlight t))

(provide 'dired-k2)

;;; dired-k2.el ends here
