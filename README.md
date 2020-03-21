# dired-k2.el

`dired-k2.el` highlights dired buffer like [k](https://github.com/supercrabtree/k).

(This may works only default dired setting)


## screenshot

### k.zsh style

![Screenshot of dired-k2 command](image/dired-k.png)


## Commands

### `dired-k2`

Highlight dired buffer by following parameters.

- File size
- Modified time
- Git status(if here is in git repository)


## Sample Configuration

### dired-k2
```lisp
(require 'dired-k2)
(define-key dired-mode-map (kbd "K") #'dired-k2)

;; You can use dired-k2 alternative to revert-buffer
(define-key dired-mode-map (kbd "g") #'dired-k2)

;; always execute dired-k2 when dired buffer is opened
(add-hook 'dired-initial-position-hook #'dired-k2)
```
