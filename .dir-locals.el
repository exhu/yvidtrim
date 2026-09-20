;;; Directory Local Variables
;;; For more information see (info "(emacs) Directory Variables")
;;; Syntax: ((MODE . ((VAR . VALUE) ...)) ...)
;;; A MODE of `nil' applies the settings to all buffers in the directory.

((nil . ((eval . (let ((root (locate-dominating-file
                                  default-directory ".dir-locals.el")))
                       (setq-local compile-command
                                   (format "ninja -C %s_build" root)))))))
