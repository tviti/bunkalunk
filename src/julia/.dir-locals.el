((julia-mode . ((eglot-ignored-server-capabilities . (:inlayHintProvider))
                (eval . (add-hook 'before-save-hook #'eglot-format-buffer nil 'local)))))
