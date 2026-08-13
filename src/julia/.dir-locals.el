;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

((julia-mode . ((julia-repl-executable-records . ((default "julia-dev") ("julia")))
		(eglot-ignored-server-capabilities . (:inlayHintProvider))
		(eval . (progn
			  (remove-hook 'before-save-hook #'eglot-format-buffer t)
			  (add-hook 'after-save-hook
				    (lambda nil
				      (call-process "runic" nil nil nil "--inplace"
						    buffer-file-name)
				      (revert-buffer t t t))
				    nil t))))))
