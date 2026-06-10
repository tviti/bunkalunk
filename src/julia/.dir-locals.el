((julia-mode . ((inferior-julia-program . "julia-dev")
                (eglot-ignored-server-capabilities . (:inlayHintProvider))
                (eval . (add-hook 'before-save-hook
				  (lambda ()
				    (eglot-format-buffer)
				    (while (accept-process-output nil 0.5)))
				  nil 'local)))))
