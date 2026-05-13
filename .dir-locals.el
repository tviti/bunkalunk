((nil . ((fill-column . 80)))
 (python-mode . ((compile-command . "pytest")
		 (python-shell-interpreter . "ipython")
		 (python-shell-interpreter-args . "--simple-prompt")
		 (eglot-workspace-configuration
		  . (:pylsp
		     (:plugins
		      ;; Disable built-in providers that overlap with ruff
		      (:pycodestyle (:enabled :json-false)
		       :pyflakes    (:enabled :json-false)
		       :mccabe      (:enabled :json-false)
		       :autopep8    (:enabled :json-false)
		       :yapf        (:enabled :json-false)
		       ;; rope: refactoring
		       :rope (:enabled t)
		       ;; ruff: linting + formatting
		       :ruff        (:enabled t :formatEnabled t)
		       ;; mypy: type checking
		       :pylsp_mypy  (:enabled t
					      :args ["--config-file" "src/python/pyproject.toml"]))))))))
