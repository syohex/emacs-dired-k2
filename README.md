# dired-k2.el

`dired-k2.el` highlights dired buffer like [k](https://github.com/supercrabtree/k).

(This may works only default dired setting)


## screenshot

### k.zsh style

![Screenshot of dired-k2 command](image/dired-k.png)

### git status --short style

![Screenshot of dired-k2 with git style](image/dired-2-style-git.png)


## Commands

### `dired-k2`

Highlight dired buffer by following parameters.

- File size
- Modified time
- Git status(if here is in git repository)

### `dired-k2-no-revert`

Same as `dired-k2`, except this command does not call `revert-buffert`.
This command can set to a hook `dired-after-readin-hook`.


## Sample Configuration

### dired-k2
```lisp
(require 'dired-k2)
(define-key dired-mode-map (kbd "K") #'dired-k2)

;; You can use dired-k2 alternative to revert-buffer
(define-key dired-mode-map (kbd "g") #'dired-k2)

;; always execute dired-k2 when dired buffer is opened
(add-hook 'dired-initial-position-hook #'dired-k2)

(add-hook 'dired-after-readin-hook #'dired-k2-no-revert)
```
