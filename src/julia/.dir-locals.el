((julia-mode . ((inferior-julia-program . "julia-dev")
                (eglot-ignored-server-capabilities . (:inlayHintProvider))
		(eval . (progn
			  (remove-hook 'before-save-hook #'eglot-format-buffer t)
			  (add-hook 'after-save-hook
				    (lambda ()
				      (call-process "runic" nil nil nil "--inplace" buffer-file-name)
				      (revert-buffer t t t))
				    nil t))))))
