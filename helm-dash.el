;;; helm-dash.el --- Helm extension to search dash docsets

;; Copyright (C) 2013  Raimon Grau
;; Copyright (C) 2013  Toni Reina

;; Author: Raimon Grau <raimonster@gmail.com>
;;         Toni Reina  <areina0@gmail.com>
;; Version: 0.1
;; Package-Requires: ((sqlite "0.1") (helm "0.0.0"))
;; Keywords: docs

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
;;
;;; Commentary:
;;
;; Clone the functionality of dash using helm foundation. Browse
;; documentation via dash docsets.
;;
;; More info in the project site https://github.com/areina/helm-dash
;;
;;; Code:

(require 'helm)
(require 'helm-match-plugin)
(require 'sqlite)
(require 'json)
(require 'ido)

(defgroup helm-dash nil
  "Experimental task management."
  :prefix "helm-dash-"
  :group 'applications)

(defcustom helm-dash-docsets-path
  (format "%s/.docsets"  (getenv "HOME"))
  "Default path for docsets."
  :group 'helm-dash)

(defcustom helm-dash-active-docsets
  '() "List of Docsets to search.")

(defcustom helm-dash-docsets-url "https://raw.github.com/Kapeli/feeds/master"
  "Foo." :group 'helm-dash)

(defcustom helm-dash-completing-read-func 'ido-completing-read
  "Completion function to be used when installing docsets.

Suggested possible values are:
 * `completing-read':       built-in completion method.
 * `ido-completing-read':   dynamic completion within the minibuffer."
  :type 'function
  :options '(completing-read ido-completing-read)
  :group 'helm-dash)

(defun helm-dash-connect-to-docset (docset)
  (sqlite-init (format
                "%s/%s.docset/Contents/Resources/docSet.dsidx"
                helm-dash-docsets-path docset)))

(defvar helm-dash-connections nil
;;; create conses like ("Go" . connection)
)

(setq helm-dash-connections nil)

(defun helm-dash-create-connections ()
  (when (not helm-dash-connections)
    (setq helm-dash-connections
          (mapcar (lambda (x)
                    (let ((connection (helm-dash-connect-to-docset x)))
                      (list x connection (helm-dash-docset-type connection))))
                  helm-dash-active-docsets))))

(defun helm-dash-reset-connections ()
  (interactive)
  (dolist (connection helm-dash-connections)
    (sqlite-bye (cadr connection)))
  (setq helm-dash-connections nil))

(defun helm-dash-docset-type (connection)
  (if (member "searchIndex" (car (sqlite-query connection ".tables")))
    "DASH"
    "ZDASH"))

(defun helm-dash-search-all-docsets ()
  (let ((url "https://api.github.com/repos/Kapeli/feeds/contents/"))
    (with-current-buffer
        (url-retrieve-synchronously url)
      (goto-char url-http-end-of-headers)
      (json-read))))

(defvar helm-dash-ignored-docsets
  '("Bootstrap" "Drupal" "Zend_Framework" "Ruby_Installed_Gems" "Man_Pages")
  "Return a list of ignored docsets.
These docsets are not available to install.
See here the reason: https://github.com/areina/helm-dash/issues/17.")

(defun helm-dash-available-docsets ()
  ""
  (delq nil (mapcar (lambda (docset)
                      (let ((name (assoc-default 'name (cdr docset))))
                        (if (and (equal (file-name-extension name) "xml")
                                 (not
                                  (member (file-name-sans-extension name) helm-dash-ignored-docsets)))
                            (file-name-sans-extension name))))
                    (helm-dash-search-all-docsets))))

(defun helm-dash-installed-docsets ()
  "Return a list of installed docsets."
  (let ((docsets (directory-files helm-dash-docsets-path nil ".docset$")))
    (mapcar '(lambda (name)
               (cond ((string-match "[^.]+" name) (match-string 0 name))
                     (t name)))
            docsets)))

;;;###autoload
(defun helm-dash-deactivate-docset (docset)
  "Deactivate DOCSET.  If called interactively prompts for the docset name."
  (interactive (list (funcall helm-dash-completing-read-func
                              "Deactivate docset: " helm-dash-active-docsets
                              nil t)))
  (setq helm-dash-active-docsets (remove docset helm-dash-active-docsets))
  (customize-save-variable 'helm-dash-active-docsets helm-dash-active-docsets)
  (helm-dash-reset-connections))

;;;###autoload
(defun helm-dash-activate-docset (docset)
  "Activate DOCSET.  If called interactively prompts for the docset name."
  (interactive (list (funcall helm-dash-completing-read-func
                              "Activate docset: " (helm-dash-installed-docsets)
                              nil t)))
  (add-to-list 'helm-dash-active-docsets docset)
  (customize-save-variable 'helm-dash-active-docsets helm-dash-active-docsets)
  (helm-dash-reset-connections))

;;;###autoload
(defun helm-dash-install-docset ()
  "Download docset with specified NAME and move its stuff to docsets-path."
  (interactive)
  (let* ((docset-name (funcall helm-dash-completing-read-func
                               "Install docset: " (helm-dash-available-docsets)))
         (feed-url (format "%s/%s.xml" helm-dash-docsets-url docset-name))
         (docset-tmp-path (format "%s%s-docset.tgz" temporary-file-directory docset-name))
         (feed-tmp-path (format "%s%s-feed.xml" temporary-file-directory docset-name)))
    (url-copy-file feed-url feed-tmp-path t)
    (url-copy-file (helm-dash-get-docset-url feed-tmp-path) docset-tmp-path t)
    (shell-command-to-string (format "tar xvf %s -C %s" docset-tmp-path helm-dash-docsets-path))
    (helm-dash-activate-docset docset-name)
    (message (format "Installed docset %s." docset-name))))

(defun helm-dash-get-docset-url (feed-path)
  ""
  (let* ((xml (xml-parse-file feed-path))
         (urls (car xml))
         (url (xml-get-children urls 'url)))
    (caddr (first url))))

(defun helm-dash-where-query (pattern)
  ""
  (let ((conditions
         (mapcar (lambda (word)
                   (format "\"name\" like \"%%%s%%\"" word))
                 (split-string pattern " "))))
    (format " WHERE %s" (mapconcat 'identity conditions " AND "))))

(defun helm-dash-search ()
  "Iterates every `helm-dash-connections' looking for the
`helm-pattern'."
  (let ((db "searchIndex")
        (full-res (list))
        (where-query (helm-dash-where-query helm-pattern))             ;let the magic happen with spaces
        )
    (dolist (docset helm-dash-connections)
      (let ((res
             (and
              ;; hack to avoid sqlite hanging (timeouting) because of no results
              (< 0 (string-to-number (caadr (sqlite-query (cadr docset)
                                                          (format
                                                           "SELECT COUNT(*) FROM %s %s"
                                                           db where-query)))))
              (sqlite-query (cadr docset)
                            (format
                             "SELECT t.type, t.name, t.path FROM %s t %s order by lower(t.name)"
                             db where-query)))))

        ;; how to do the appending properly?
        (setq full-res
              (append full-res
                      (mapcar (lambda (x)
                                (cons (format "%s - %s"  (cadr docset) (cadr x)) (format "%s%s%s%s"
                                                          "file://"
                                                          helm-dash-docsets-path
                                                          (format "/%s.docset/Contents/Resources/Documents/"
																																	(car docset))
                                                          (caddr x))))
                              res)))))
    full-res))

(defun helm-dash-actions (actions doc-item) `(("Go to doc" . browse-url)))

(defvar helm-source-dash-search
  '((name . "Dash")
    (volatile)
    (delayed)
    (requires-pattern . 3)
    (candidates-process . helm-dash-search)
    (action-transformer . helm-dash-actions)))

;;;###autoload
(defun helm-dash ()
  "Bring up a Dash search interface in helm."
  (interactive)
  (helm-dash-create-connections)
  (helm :sources '(helm-source-dash-search)
	:buffer "*helm-dash*"))

(provide 'helm-dash)

;;; helm-dash.el ends here
