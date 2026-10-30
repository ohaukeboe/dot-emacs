;;; lsp-mcp.el --- LSP MCP server for Emacs -*- lexical-binding: t; -*-

;; Author: Oskar Haukebøe
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (lsp-mode "9.0") (mcp-server-lib "0.1"))
;; Emacs 30.1 for `derived-mode-all-parents', which `lsp-mcp-enabled-mode-p'
;; walks to find the mode whose hook starts a server.

;;; Commentary:
;; Exposes lsp-mode functionality as MCP tools so LLM agents can use the
;; same LSP capabilities configured in Emacs: go-to-definition, references,
;; hover, diagnostics, and symbol search.

;;; Code:

(require 'lsp-mode)
(require 'mcp-server-lib)

(defconst lsp-mcp--server-id "lsp-mcp")

(defconst lsp-mcp--symbol-kind-names
  '((1 . "File") (2 . "Module") (3 . "Namespace") (4 . "Package")
    (5 . "Class") (6 . "Method") (7 . "Property") (8 . "Field")
    (9 . "Constructor") (10 . "Enum") (11 . "Interface") (12 . "Function")
    (13 . "Variable") (14 . "Constant") (15 . "String") (16 . "Number")
    (17 . "Boolean") (18 . "Array") (19 . "Object") (20 . "Key")
    (21 . "Null") (22 . "EnumMember") (23 . "Struct") (24 . "Event")
    (25 . "Operator") (26 . "TypeParameter")))

(defconst lsp-mcp--diagnostic-severity-names
  '((1 . "error") (2 . "warning") (3 . "information") (4 . "hint")))

;;; LSP-enabled modes

(defun lsp-mcp-enabled-mode-p (&optional mode)
  "Return the LSP client MODE starts, or nil if MODE is not LSP-enabled.
MODE defaults to the current buffer's `major-mode'.  MODE is LSP-enabled
when its hook, or the hook of a mode it derives from, contains `lsp' or
`lsp-deferred' (returns `lsp-mode') or `eglot-ensure' (returns `eglot').
The nearest mode with such a hook decides."
  (cl-some (lambda (m)
             (let* ((hook (intern (format "%s-hook" m)))
                    (fns (and (boundp hook) (default-value hook))))
               (cond ((or (memq 'lsp fns) (memq 'lsp-deferred fns)) 'lsp-mode)
                     ((memq 'eglot-ensure fns) 'eglot))))
           (derived-mode-all-parents (or mode major-mode))))

;;; Helpers

;; mcp-server-lib has no async tools: a tool holds Emacs until it returns.
;; So tools never wait for a server to start, and requests time out fast.

(defconst lsp-mcp--response-timeout 3
  "Seconds a tool waits for an LSP response; binds `lsp-response-timeout'.")

(defvar-local lsp-mcp--own-buffer nil
  "Non-nil in a buffer lsp-mcp opened itself, where it may start a server.")
(put 'lsp-mcp--own-buffer 'permanent-local t)

(defun lsp-mcp--workspaces-ready-p ()
  "Return non-nil when all workspaces for current buffer are initialized."
  (when-let ((workspaces (and (bound-and-true-p lsp-mode) (lsp-workspaces))))
    (cl-every (lambda (ws) (eq (lsp--workspace-status ws) 'initialized))
              workspaces)))

(defun lsp-mcp--start-server (buf)
  "Start lsp-mode in BUF unless it is dead or already has it.
Run from a timer, so a failure must not escape as a timer error.  Nobody
is there to answer a prompt, so the project root is guessed and any
question lsp-mode asks gets a \"no\"."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (unless (bound-and-true-p lsp-mode)
        (condition-case err
            (let ((lsp-auto-guess-root t))
              (cl-letf (((symbol-function 'y-or-n-p) #'ignore)
                        ((symbol-function 'yes-or-no-p) #'ignore))
                (lsp)))
          (error (message "lsp-mcp: starting LSP in %s failed: %S"
                          (buffer-name) err)))))))

(defun lsp-mcp--ensure-lsp-buffer (file-path)
  "Return a buffer visiting FILE-PATH with an initialized lsp-mode server.
Never waits for a server.  Throws an MCP tool error if the file is
missing, its mode is not an LSP-enabled mode using lsp-mode, or the user
already had it open without lsp-mode.  If the server is not ready yet,
schedules its start (only in a buffer lsp-mcp opened) and throws an
error asking the agent to retry."
  (unless (file-exists-p file-path)
    (mcp-server-lib-tool-throw (format "File not found: %s" file-path)))
  (let* ((abs (expand-file-name file-path))
         (existing (find-buffer-visiting abs))
         (buf (or existing
                  (with-current-buffer (find-file-noselect abs)
                    (setq lsp-mcp--own-buffer t)
                    (current-buffer)))))
    (with-current-buffer buf
      (cond
       ((lsp-mcp--workspaces-ready-p) buf)
       ((or (not (eq (lsp-mcp-enabled-mode-p) 'lsp-mode))
            (and (not lsp-mcp--own-buffer)
                 (not (bound-and-true-p lsp-mode))))
        (mcp-server-lib-tool-throw
         (format "lsp-mode is not active in %s (major-mode: %s)"
                 file-path major-mode)))
       (t
        (unless (bound-and-true-p lsp-mode)
          (run-at-time 0 nil #'lsp-mcp--start-server buf))
        (mcp-server-lib-tool-throw
         (format "LSP server for %s is starting; retry in a few seconds."
                 file-path)))))))

(defun lsp-mcp--timeout-error-p (err)
  "Return non-nil if ERR is lsp-mode giving up waiting for a response."
  (or (eq (car err) 'lsp-timed-out-error)
      (string-prefix-p "Timeout while waiting for response"
                       (error-message-string err))))

(defmacro lsp-mcp--with-tool-handling (&rest body)
  "Run tool BODY with a short LSP timeout, turning errors into tool errors.
Tool errors pass through unchanged, a timed-out request asks the agent to
retry, and any other error is reported with its data."
  (declare (indent 0) (debug t))
  `(condition-case err
       (let ((lsp-response-timeout lsp-mcp--response-timeout))
         ,@body)
     (mcp-server-lib-tool-error (signal (car err) (cdr err)))
     (error
      (mcp-server-lib-tool-throw
       (if (lsp-mcp--timeout-error-p err)
           "LSP request timed out; retry"
         (format "Error: %S" err))))))

(defun lsp-mcp--position-params (file-path line column)
  "LSP TextDocumentPositionParams for FILE-PATH at LINE (1-indexed) COLUMN (0-indexed)."
  (list :textDocument (list :uri (lsp--path-to-uri (expand-file-name file-path)))
        :position (list :line (1- line) :character column)))

(defun lsp-mcp--location-to-alist (loc)
  "Convert LSP Location LOC (plist or hash-table) to an alist."
  (let* ((uri (lsp-get loc :uri))
         (start (lsp-get (lsp-get loc :range) :start)))
    `((file . ,(lsp--uri-to-path uri))
      (line . ,(1+ (lsp-get start :line)))
      (column . ,(lsp-get start :character)))))

(defun lsp-mcp--location-link-to-alist (loc-link)
  "Convert LSP LocationLink LOC-LINK (plist or hash-table) to an alist."
  (let* ((uri (lsp-get loc-link :targetUri))
         (start (lsp-get (lsp-get loc-link :targetRange) :start)))
    `((file . ,(lsp--uri-to-path uri))
      (line . ,(1+ (lsp-get start :line)))
      (column . ,(lsp-get start :character)))))

(defun lsp-mcp--location-p (obj)
  "Return non-nil if OBJ is a Location (has :uri), else nil for LocationLink."
  (lsp-get obj :uri))

(defun lsp-mcp--normalize-locations (response)
  "Convert a definition/references RESPONSE to a list of location alists.
Handles: null, single Location, Location[], LocationLink[]."
  (cond
   ((null response) nil)
   ((vectorp response)
    (if (= (length response) 0)
        nil
      (let ((items (append response nil)))
        (if (lsp-mcp--location-p (car items))
            (mapcar #'lsp-mcp--location-to-alist items)
          (mapcar #'lsp-mcp--location-link-to-alist items)))))
   (t
    (if (lsp-mcp--location-p response)
        (list (lsp-mcp--location-to-alist response))
      (list (lsp-mcp--location-link-to-alist response))))))

(defun lsp-mcp--symbol-kind-name (kind)
  "Return string name for LSP SymbolKind integer KIND."
  (or (cdr (assq kind lsp-mcp--symbol-kind-names))
      (number-to-string kind)))

(defun lsp-mcp--any-lsp-buffer ()
  "Return the first buffer with lsp-mode active, or nil."
  (cl-find-if (lambda (buf)
                (with-current-buffer buf
                  (bound-and-true-p lsp-mode)))
              (buffer-list)))

(defun lsp-mcp--parse-int (val)
  "Parse VAL as an integer, accepting both string and number input."
  (if (stringp val) (string-to-number val) val))

;;; Tool handlers

(defun lsp-mcp--find-definitions (file line column)
  "Find definitions of the symbol at FILE LINE COLUMN via LSP.

MCP Parameters:
  file   - Absolute path to the file
  line   - Line number (1-indexed)
  column - Column number (0-indexed)"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file))
          (params (lsp-mcp--position-params file
                                            (lsp-mcp--parse-int line)
                                            (lsp-mcp--parse-int column))))
      (with-current-buffer buf
        (json-encode (lsp-mcp--normalize-locations
                      (lsp-request "textDocument/definition" params)))))))

(defun lsp-mcp--find-references (file line column)
  "Find all references to the symbol at FILE LINE COLUMN via LSP.

MCP Parameters:
  file   - Absolute path to the file
  line   - Line number (1-indexed)
  column - Column number (0-indexed)"
  (lsp-mcp--with-tool-handling
    (let* ((buf (lsp-mcp--ensure-lsp-buffer file))
           (params (append (lsp-mcp--position-params file
                                                     (lsp-mcp--parse-int line)
                                                     (lsp-mcp--parse-int column))
                           (list :context (list :includeDeclaration t)))))
      (with-current-buffer buf
        (json-encode (lsp-mcp--normalize-locations
                      (lsp-request "textDocument/references" params)))))))

(defun lsp-mcp--hover (file line column)
  "Get hover documentation for the symbol at FILE LINE COLUMN via LSP.

MCP Parameters:
  file   - Absolute path to the file
  line   - Line number (1-indexed)
  column - Column number (0-indexed)"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file))
          (params (lsp-mcp--position-params file
                                            (lsp-mcp--parse-int line)
                                            (lsp-mcp--parse-int column))))
      (with-current-buffer buf
        (let ((response (lsp-request "textDocument/hover" params)))
          (if (null response)
              ""
            (let ((contents (lsp-get response :contents)))
              (cond
               ((null contents) "")
               ((stringp contents) contents)
               ;; Array of MarkedString
               ((vectorp contents)
                (mapconcat (lambda (item)
                             (if (stringp item) item
                               (or (lsp-get item :value) "")))
                           (append contents nil)
                           "\n"))
               ;; MarkupContent { kind, value } as plist or hash
               (t (or (lsp-get contents :value)
                      (format "%s" contents)))))))))))

(defun lsp-mcp--get-diagnostics (file)
  "Get LSP diagnostics for FILE.

MCP Parameters:
  file - Absolute path to the file"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file)))
      (with-current-buffer buf
        (let* ((path (expand-file-name file))
               (diags (gethash path (lsp-diagnostics))))
          (if (null diags)
              "[]"
            (json-encode
             (mapcar (lambda (diag)
                       (let* ((start (lsp-get (lsp-get diag :range) :start))
                              (sev (lsp-get diag :severity))
                              (code (lsp-get diag :code)))
                         `((severity . ,(if sev
                                            (or (cdr (assq sev lsp-mcp--diagnostic-severity-names))
                                                (number-to-string sev))
                                          "unknown"))
                           (line . ,(1+ (lsp-get start :line)))
                           (column . ,(lsp-get start :character))
                           (message . ,(lsp-get diag :message))
                           ,@(when code `((code . ,code))))))
                     diags))))))))

(defun lsp-mcp--workspace-symbols (query)
  "Search workspace symbols matching QUERY via LSP.

MCP Parameters:
  query - Search string for symbol names (empty string returns all symbols)"
  (lsp-mcp--with-tool-handling
    (let ((any-buf (lsp-mcp--any-lsp-buffer)))
      (unless any-buf
        (mcp-server-lib-tool-throw "No active LSP buffers found"))
      (with-current-buffer any-buf
        (let ((response (lsp-request "workspace/symbol" (list :query query))))
          (if (or (null response) (= (length response) 0))
              "[]"
            (json-encode
             (mapcar (lambda (sym)
                       (let* ((loc (lsp-get sym :location))
                              (kind (lsp-get sym :kind))
                              (name (lsp-get sym :name))
                              (range (lsp-get loc :range)))
                         ;; loc can be a Location {uri, range} or just {uri} (WorkspaceSymbol)
                         (if range
                             (let* ((start (lsp-get range :start)))
                               `((name . ,name)
                                 (kind . ,(lsp-mcp--symbol-kind-name kind))
                                 (file . ,(lsp--uri-to-path (lsp-get loc :uri)))
                                 (line . ,(1+ (lsp-get start :line)))
                                 (column . ,(lsp-get start :character))))
                           `((name . ,name)
                             (kind . ,(lsp-mcp--symbol-kind-name kind))
                             (file . ,(lsp--uri-to-path (lsp-get loc :uri)))))))
                     (append response nil)))))))))

(defun lsp-mcp--document-symbols-flatten (syms &optional parent-name)
  "Flatten DocumentSymbol tree SYMS into a list of alists.
PARENT-NAME provides the breadcrumb prefix for nested symbols.
Parents appear before their children in the returned list."
  (let (result)
    (dolist (sym (append syms nil))
      (let* ((name (lsp-get sym :name))
             (kind (lsp-get sym :kind))
             (detail (or (lsp-get sym :detail) ""))
             (start (lsp-get (lsp-get sym :selectionRange) :start))
             (children (lsp-get sym :children))
             (full-name (if parent-name (concat parent-name "." name) name)))
        (push `((name . ,full-name)
                (kind . ,(lsp-mcp--symbol-kind-name kind))
                (line . ,(1+ (lsp-get start :line)))
                (column . ,(lsp-get start :character))
                ,@(when (and detail (not (string-empty-p detail)))
                    `((detail . ,detail))))
              result)
        (when (and children (> (length children) 0))
          (dolist (child (lsp-mcp--document-symbols-flatten
                          children full-name))
            (push child result)))))
    (nreverse result)))

(defun lsp-mcp--document-symbols (file)
  "Get all symbols defined in FILE via LSP.

MCP Parameters:
  file - Absolute path to the file"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file)))
      (with-current-buffer buf
        (let* ((params (list :textDocument
                             (list :uri (lsp--path-to-uri (expand-file-name file)))))
               (response (lsp-request "textDocument/documentSymbol" params)))
          (if (or (null response) (= (length response) 0))
              "[]"
            (let ((items (append response nil)))
              (json-encode
               (if (lsp-get (car items) :selectionRange)
                   ;; DocumentSymbol[] (hierarchical) — has selectionRange
                   (lsp-mcp--document-symbols-flatten items)
                 ;; SymbolInformation[] (flat) — has location
                 (mapcar (lambda (sym)
                           (let* ((loc (lsp-get sym :location))
                                  (start (lsp-get (lsp-get loc :range) :start))
                                  (kind (lsp-get sym :kind)))
                             `((name . ,(lsp-get sym :name))
                               (kind . ,(lsp-mcp--symbol-kind-name kind))
                               (line . ,(1+ (lsp-get start :line)))
                               (column . ,(lsp-get start :character)))))
                         items))))))))))

;;; New navigation tools

(defun lsp-mcp--find-implementations (file line column)
  "Find implementations of the interface/abstract symbol at FILE LINE COLUMN.

MCP Parameters:
  file   - Absolute path to the file
  line   - Line number (1-indexed)
  column - Column number (0-indexed)"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file))
          (params (lsp-mcp--position-params file
                                            (lsp-mcp--parse-int line)
                                            (lsp-mcp--parse-int column))))
      (with-current-buffer buf
        (json-encode (lsp-mcp--normalize-locations
                      (lsp-request "textDocument/implementation" params)))))))

(defun lsp-mcp--find-type-definition (file line column)
  "Find the type definition of the symbol at FILE LINE COLUMN.

MCP Parameters:
  file   - Absolute path to the file
  line   - Line number (1-indexed)
  column - Column number (0-indexed)"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file))
          (params (lsp-mcp--position-params file
                                            (lsp-mcp--parse-int line)
                                            (lsp-mcp--parse-int column))))
      (with-current-buffer buf
        (json-encode (lsp-mcp--normalize-locations
                      (lsp-request "textDocument/typeDefinition" params)))))))

(defun lsp-mcp--call-hierarchy-item-to-alist (item)
  "Convert a CallHierarchyItem ITEM to an alist."
  (let* ((uri  (lsp-get item :uri))
         (kind (lsp-get item :kind))
         (start (lsp-get (lsp-get item :range) :start)))
    `((name . ,(lsp-get item :name))
      (kind . ,(lsp-mcp--symbol-kind-name kind))
      (file . ,(lsp--uri-to-path uri))
      (line . ,(1+ (lsp-get start :line)))
      (column . ,(lsp-get start :character)))))

(defun lsp-mcp--call-hierarchy (file line column direction)
  "Get call hierarchy for the symbol at FILE LINE COLUMN.
DIRECTION is either \"incoming\" (callers) or \"outgoing\" (callees).

MCP Parameters:
  file      - Absolute path to the file
  line      - Line number (1-indexed)
  column    - Column number (0-indexed)
  direction - \"incoming\" for callers, \"outgoing\" for callees"
  (lsp-mcp--with-tool-handling
    (let* ((buf (lsp-mcp--ensure-lsp-buffer file))
           (params (lsp-mcp--position-params file
                                             (lsp-mcp--parse-int line)
                                             (lsp-mcp--parse-int column)))
           (method (if (string= direction "outgoing")
                       "callHierarchy/outgoingCalls"
                     "callHierarchy/incomingCalls")))
      (with-current-buffer buf
        (let ((items (lsp-request "textDocument/prepareCallHierarchy" params)))
          (if (or (null items) (= (length items) 0))
              "[]"
            (let* ((item (aref items 0))
                   (calls (lsp-request method (list :item item))))
              (if (or (null calls) (= (length calls) 0))
                  "[]"
                (json-encode
                 (mapcar (lambda (call)
                           (let* ((other-key (if (string= direction "outgoing") :to :from))
                                  (other (lsp-get call other-key))
                                  (ranges (lsp-get call :fromRanges))
                                  (sites (when (and ranges (> (length ranges) 0))
                                           (mapcar (lambda (r)
                                                     (lsp-get (lsp-get r :start) :line))
                                                   (append ranges nil)))))
                             (append
                              (lsp-mcp--call-hierarchy-item-to-alist other)
                              (when sites
                                `((call-sites . ,(vconcat (mapcar #'1+ sites))))))))
                         (append calls nil)))))))))))

(defun lsp-mcp--signature-help (file line column)
  "Get signature help for the call at FILE LINE COLUMN via LSP.

MCP Parameters:
  file   - Absolute path to the file
  line   - Line number (1-indexed)
  column - Column number (0-indexed)"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file))
          (params (lsp-mcp--position-params file
                                            (lsp-mcp--parse-int line)
                                            (lsp-mcp--parse-int column))))
      (with-current-buffer buf
        (let ((response (lsp-request "textDocument/signatureHelp" params)))
          (if (null response)
              "[]"
            (let* ((sigs (lsp-get response :signatures))
                   (active-sig (or (lsp-get response :activeSignature) 0))
                   (active-param (lsp-get response :activeParameter)))
              (if (or (null sigs) (= (length sigs) 0))
                  "[]"
                (json-encode
                 (mapcar (lambda (sig)
                           (let* ((label (lsp-get sig :label))
                                  (doc   (lsp-get sig :documentation))
                                  (doc-str (cond
                                            ((null doc) nil)
                                            ((stringp doc) doc)
                                            (t (lsp-get doc :value))))
                                  (params-raw (lsp-get sig :parameters))
                                  (params-list
                                   (when (and params-raw (> (length params-raw) 0))
                                     (mapcar (lambda (p)
                                               (let* ((plabel (lsp-get p :label))
                                                      (pdoc   (lsp-get p :documentation))
                                                      (pdoc-str (cond
                                                                 ((null pdoc) nil)
                                                                 ((stringp pdoc) pdoc)
                                                                 (t (lsp-get pdoc :value)))))
                                                 (append
                                                  `((label . ,(if (vectorp plabel)
                                                                  (substring label
                                                                             (aref plabel 0)
                                                                             (aref plabel 1))
                                                                plabel)))
                                                  (when pdoc-str `((documentation . ,pdoc-str))))))
                                             (append params-raw nil)))))
                             (append
                              `((label . ,label))
                              (when doc-str `((documentation . ,doc-str)))
                              (when params-list `((parameters . ,(vconcat params-list))))
                              `((active . ,(= (cl-position sig (append sigs nil)) active-sig)))
                              (when active-param `((activeParameter . ,active-param))))))
                         (append sigs nil)))))))))))

(defun lsp-mcp--inlay-hints (file)
  "Get inlay hints (inferred types, parameter names) for FILE via LSP.

MCP Parameters:
  file - Absolute path to the file"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file)))
      (with-current-buffer buf
        (let* ((params
                (list :textDocument
                      (list :uri (lsp--path-to-uri (expand-file-name file)))
                      :range
                      (list :start (list :line 0 :character 0)
                            :end   (list :line most-positive-fixnum :character 0))))
               (response (lsp-request "textDocument/inlayHint" params)))
          (if (or (null response) (= (length response) 0))
              "[]"
            (json-encode
             (mapcar (lambda (hint)
                       (let* ((pos  (lsp-get hint :position))
                              (kind (lsp-get hint :kind))
                              (kind-str (cond ((eq kind 1) "type")
                                              ((eq kind 2) "parameter")
                                              (t "other")))
                              (label (lsp-get hint :label))
                              (label-str (cond
                                          ((stringp label) label)
                                          ((vectorp label)
                                           (mapconcat (lambda (part)
                                                        (lsp-get part :value))
                                                      (append label nil)
                                                      ""))
                                          (t (format "%s" label)))))
                         `((line   . ,(1+ (lsp-get pos :line)))
                           (column . ,(lsp-get pos :character))
                           (kind   . ,kind-str)
                           (label  . ,label-str))))
                     (append response nil)))))))))

(defun lsp-mcp--document-highlight (file line column)
  "Get read/write highlights for the symbol at FILE LINE COLUMN.

MCP Parameters:
  file   - Absolute path to the file
  line   - Line number (1-indexed)
  column - Column number (0-indexed)"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file))
          (params (lsp-mcp--position-params file
                                            (lsp-mcp--parse-int line)
                                            (lsp-mcp--parse-int column))))
      (with-current-buffer buf
        (let ((response (lsp-request "textDocument/documentHighlight" params)))
          (if (or (null response) (= (length response) 0))
              "[]"
            (json-encode
             (mapcar (lambda (hl)
                       (let* ((start (lsp-get (lsp-get hl :range) :start))
                              (end   (lsp-get (lsp-get hl :range) :end))
                              (kind  (or (lsp-get hl :kind) 1))
                              (kind-str (cond ((eq kind 1) "text")
                                              ((eq kind 2) "read")
                                              ((eq kind 3) "write")
                                              (t "text"))))
                         `((kind        . ,kind-str)
                           (line        . ,(1+ (lsp-get start :line)))
                           (column      . ,(lsp-get start :character))
                           (end-line    . ,(1+ (lsp-get end :line)))
                           (end-column  . ,(lsp-get end :character)))))
                     (append response nil)))))))))

;;; Formatting tools

(defun lsp-mcp--line-col-to-pos (line column)
  "Return buffer position for LINE (1-indexed) and COLUMN (0-indexed)."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line))
    (move-to-column column)
    (point)))

(defun lsp-mcp--format-buffer (file)
  "Format FILE using the LSP server and save it.
Skips formatting if `lsp-format-buffer-on-save' is nil in the buffer.

MCP Parameters:
  file - Absolute path to the file"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file)))
      (with-current-buffer buf
        (if lsp-format-buffer-on-save
            (progn (lsp-format-buffer) (save-buffer) "formatted")
          "skipped (lsp-format-buffer-on-save is nil)")))))

(defun lsp-mcp--format-region (file start-line start-column end-line end-column)
  "Format a region of FILE using the LSP server and save it.
Skips formatting if `lsp-format-buffer-on-save' is nil in the buffer.

MCP Parameters:
  file         - Absolute path to the file
  start-line   - Start line (1-indexed)
  start-column - Start column (0-indexed)
  end-line     - End line (1-indexed)
  end-column   - End column (0-indexed)"
  (lsp-mcp--with-tool-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file)))
      (with-current-buffer buf
        (if lsp-format-buffer-on-save
            (let ((s (lsp-mcp--line-col-to-pos (lsp-mcp--parse-int start-line)
                                               (lsp-mcp--parse-int start-column)))
                  (e (lsp-mcp--line-col-to-pos (lsp-mcp--parse-int end-line)
                                               (lsp-mcp--parse-int end-column))))
              (lsp-format-region s e)
              (save-buffer)
              "formatted")
          "skipped (lsp-format-buffer-on-save is nil)")))))

;;; Restarting servers

;; eglot is optional: lsp-mcp loads without it and restarts its servers
;; only when it is loaded.
;; eglot has no public way to list every server of a project:
;; `eglot-current-server' finds only the one managing the current buffer's
;; major mode, while a manifest edit should restart them all.
(defvar eglot--servers-by-project)
(defvar eglot-sync-connect)
(declare-function eglot-reconnect "eglot" (server &optional interactive))
(declare-function eglot--server-info "eglot" (server))
(declare-function jsonrpc-name "jsonrpc" (connection))

(defun lsp-mcp--restart-lsp-mode (file)
  "Restart the lsp-mode workspaces of FILE's project; return their names."
  (when-let* ((session (lsp-session))
              (folder (lsp-find-session-folder session file)))
    (mapcar (lambda (ws)
              (lsp-workspace-restart ws)
              (symbol-name (lsp--workspace-server-id ws)))
            (gethash folder (lsp-session-folder->servers session)))))

(defun lsp-mcp--restart-eglot (file)
  "Reconnect the eglot servers of FILE's project; return their names.
Does not wait for the servers to come back up."
  (when-let* (((featurep 'eglot))
              (project (project-current nil (file-name-directory file))))
    (mapcar (lambda (server)
              (let ((eglot-sync-connect nil))
                (eglot-reconnect server))
              (or (plist-get (eglot--server-info server) :name)
                  (jsonrpc-name server)))
            (gethash project eglot--servers-by-project))))

(defun lsp-mcp--restart-workspace (file)
  "Restart the language servers of FILE's project.

MCP Parameters:
  file - Absolute path to a file in the project"
  (lsp-mcp--with-tool-handling
    (let* ((abs (expand-file-name file))
           (names (append (lsp-mcp--restart-lsp-mode abs)
                          (lsp-mcp--restart-eglot abs))))
      (if names
          (concat "Restarted: " (string-join names ", "))
        "no server running"))))

;;; Enable / Disable

;;;###autoload
(defun lsp-mcp-enable ()
  "Register LSP MCP tools with mcp-server-lib."
  (interactive)
  (mcp-server-lib-register-tool
   #'lsp-mcp--find-definitions
   :id "lsp-find-definitions"
   :server-id lsp-mcp--server-id
   :description "Find definitions of the symbol at file:line:column via LSP. Returns JSON array of {file, line, column}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--find-references
   :id "lsp-find-references"
   :server-id lsp-mcp--server-id
   :description "Find all references to the symbol at file:line:column via LSP. Returns JSON array of {file, line, column}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--hover
   :id "lsp-hover"
   :server-id lsp-mcp--server-id
   :description "Get hover documentation for the symbol at file:line:column via LSP. Returns markdown or plain text."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--get-diagnostics
   :id "lsp-get-diagnostics"
   :server-id lsp-mcp--server-id
   :description "Get LSP diagnostics (errors, warnings) for a file. Returns JSON array of {severity, line, column, message, code?}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--workspace-symbols
   :id "lsp-workspace-symbols"
   :server-id lsp-mcp--server-id
   :description "Search symbols across the entire LSP workspace by query string. Returns JSON array of {name, kind, file, line, column}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--document-symbols
   :id "lsp-document-symbols"
   :server-id lsp-mcp--server-id
   :description "Get all symbols defined in a file via LSP. Returns JSON array of {name, kind, line, column, detail?}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--find-implementations
   :id "lsp-find-implementations"
   :server-id lsp-mcp--server-id
   :description "Find concrete implementations of an interface or abstract method at file:line:column. Returns JSON array of {file, line, column}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--find-type-definition
   :id "lsp-find-type-definition"
   :server-id lsp-mcp--server-id
   :description "Find the type definition of the symbol at file:line:column (e.g. the struct a function returns). Returns JSON array of {file, line, column}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--call-hierarchy
   :id "lsp-call-hierarchy"
   :server-id lsp-mcp--server-id
   :description "Get callers or callees of the function at file:line:column. direction=\"incoming\" for callers, \"outgoing\" for callees. Returns JSON array of {name, kind, file, line, column, call-sites?}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--signature-help
   :id "lsp-signature-help"
   :server-id lsp-mcp--server-id
   :description "Get function signature(s) at a call site at file:line:column. Returns JSON array of {label, documentation?, parameters?, active, activeParameter?}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--inlay-hints
   :id "lsp-inlay-hints"
   :server-id lsp-mcp--server-id
   :description "Get inlay hints (inferred types, parameter names) for a file. Returns JSON array of {line, column, kind, label}."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--document-highlight
   :id "lsp-document-highlight"
   :server-id lsp-mcp--server-id
   :description "Get read/write highlights for the symbol at file:line:column within the same file. Returns JSON array of {kind, line, column, end-line, end-column}. kind is \"read\", \"write\", or \"text\"."
   :read-only t)
  (mcp-server-lib-register-tool
   #'lsp-mcp--format-buffer
   :id "lsp-format-buffer"
   :server-id lsp-mcp--server-id
   :description "Format an entire file using the LSP server and save it. Returns \"formatted\".")
  (mcp-server-lib-register-tool
   #'lsp-mcp--format-region
   :id "lsp-format-region"
   :server-id lsp-mcp--server-id
   :description "Format a region of a file using the LSP server and save it. start-line/end-line are 1-indexed, start-column/end-column are 0-indexed. Returns \"formatted\".")
  (mcp-server-lib-register-tool
   #'lsp-mcp--restart-workspace
   :id "lsp-restart-workspace"
   :server-id lsp-mcp--server-id
   :description "Restart the language servers (lsp-mode or eglot) for the project containing file. Call it yourself, without asking the user, after changing dependencies (once they are installed), build configuration or generated code, so diagnostics and navigation are not stale. Returns at once without waiting for the servers to come back: \"Restarted: <server names>\" or \"no server running\"."))

;;;###autoload
(defun lsp-mcp-disable ()
  "Unregister LSP MCP tools from mcp-server-lib."
  (interactive)
  (dolist (id '("lsp-find-definitions" "lsp-find-references" "lsp-hover"
                "lsp-get-diagnostics" "lsp-workspace-symbols" "lsp-document-symbols"
                "lsp-find-implementations" "lsp-find-type-definition" "lsp-call-hierarchy"
                "lsp-signature-help" "lsp-inlay-hints" "lsp-document-highlight"
                "lsp-format-buffer" "lsp-format-region" "lsp-restart-workspace"))
    (mcp-server-lib-unregister-tool id lsp-mcp--server-id)))

(provide 'lsp-mcp)

;;; lsp-mcp.el ends here
