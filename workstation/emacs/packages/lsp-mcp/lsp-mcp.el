;;; lsp-mcp.el --- LSP MCP server for Emacs -*- lexical-binding: t; -*-

;; Author: Oskar Haukebøe
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (lsp-mode "9.0") (mcp-server-lib "0.1"))

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

;;; Helpers

(defconst lsp-mcp--init-timeout 15
  "Seconds to wait for an LSP workspace to reach `initialized' status.")

(defun lsp-mcp--workspaces-ready-p ()
  "Return non-nil when all workspaces for current buffer are initialized."
  (when-let ((workspaces (lsp-workspaces)))
    (cl-every (lambda (ws) (eq (lsp--workspace-status ws) 'initialized))
              workspaces)))

(defun lsp-mcp--accept-output-until (predicate timeout)
  "Pump process output until PREDICATE returns non-nil or TIMEOUT seconds pass.
Return non-nil if PREDICATE eventually held."
  (let ((deadline (+ (float-time) timeout)))
    (while (and (< (float-time) deadline)
                (not (funcall predicate)))
      (accept-process-output nil 0.1))
    (funcall predicate)))

(defun lsp-mcp--ensure-lsp-buffer (file-path)
  "Return a buffer visiting FILE-PATH with `lsp-mode' active.
Opens the file if needed but never starts LSP — relies on lsp-mode's own
hooks to activate it.  Throws an MCP tool error if the file is missing,
lsp-mode is not active after opening (i.e. not configured for this
major-mode), or the workspace times out initializing."
  (unless (file-exists-p file-path)
    (mcp-server-lib-tool-throw (format "File not found: %s" file-path)))
  (let* ((abs (expand-file-name file-path))
         (existing (find-buffer-visiting abs))
         (buf (or existing (find-file-noselect abs))))
    (with-current-buffer buf
      (unless (bound-and-true-p lsp-mode)
        (mcp-server-lib-tool-throw
         (format "lsp-mode is not active in %s (major-mode: %s)"
                 file-path major-mode)))
      (unless (lsp-mcp--accept-output-until
               #'lsp-mcp--workspaces-ready-p
               lsp-mcp--init-timeout)
        (mcp-server-lib-tool-throw
         (format "Timed out after %ds waiting for LSP workspace in %s"
                 lsp-mcp--init-timeout file-path))))
    buf))

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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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
  (mcp-server-lib-with-error-handling
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

MCP Parameters:
  file - Absolute path to the file"
  (mcp-server-lib-with-error-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file)))
      (with-current-buffer buf
        (lsp-format-buffer)
        (save-buffer))
      "formatted")))

(defun lsp-mcp--format-region (file start-line start-column end-line end-column)
  "Format a region of FILE using the LSP server and save it.

MCP Parameters:
  file         - Absolute path to the file
  start-line   - Start line (1-indexed)
  start-column - Start column (0-indexed)
  end-line     - End line (1-indexed)
  end-column   - End column (0-indexed)"
  (mcp-server-lib-with-error-handling
    (let ((buf (lsp-mcp--ensure-lsp-buffer file)))
      (with-current-buffer buf
        (let ((s (lsp-mcp--line-col-to-pos (lsp-mcp--parse-int start-line)
                                           (lsp-mcp--parse-int start-column)))
              (e (lsp-mcp--line-col-to-pos (lsp-mcp--parse-int end-line)
                                           (lsp-mcp--parse-int end-column))))
          (lsp-format-region s e)
          (save-buffer)))
      "formatted")))

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
   :description "Format a region of a file using the LSP server and save it. start-line/end-line are 1-indexed, start-column/end-column are 0-indexed. Returns \"formatted\"."))

;;;###autoload
(defun lsp-mcp-disable ()
  "Unregister LSP MCP tools from mcp-server-lib."
  (interactive)
  (dolist (id '("lsp-find-definitions" "lsp-find-references" "lsp-hover"
                "lsp-get-diagnostics" "lsp-workspace-symbols" "lsp-document-symbols"
                "lsp-find-implementations" "lsp-find-type-definition" "lsp-call-hierarchy"
                "lsp-signature-help" "lsp-inlay-hints" "lsp-document-highlight"
                "lsp-format-buffer" "lsp-format-region"))
    (mcp-server-lib-unregister-tool id lsp-mcp--server-id)))

(provide 'lsp-mcp)

;;; lsp-mcp.el ends here
